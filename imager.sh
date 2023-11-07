#!/bin/bash

#/# Usage: imager.sh <command> <options>
#/#
#/# Commands:
#/#     list-disks [--all]
#/#         List available disks for imaging. Defaults to physical,
#/#         external disks. Use the --all flag to see all disks.
#/#
#/#     list-images
#/#         List available images. Defaults to 64-bit OS images.
#/#
#/#     image DISK
#/#         Image the storage device and pre-configure bdr-pi
#/#         installation scripting.
#/#
#/#     clear-cache
#/#         Clear the local cache of images and image detatils.
#/#

set -u
set -o pipefail


# push_dir <dir> invokes pushd and aborts the script on error.
push_dir() {
    pushd "${1}" >/dev/null || abort "could not change to ${1}"
}

# pop_dir invokes popd and aborts the script on error.
pop_dir() {
    popd >/dev/null || abort "could not pop dir"
}

# installed <app> returns success if the given app is on the PATH.
installed() {
    local BINARY="$1"
    hash "${BINARY}" 2> /dev/null
    return $?
}

# perror prints its arguments to stderr.
perror() {
    printf "%s\n" "$@" >/dev/stderr
    return 0
}

# abort prints its arguments and quits
abort() {
    perror "$@"
    exit 1
}

# report prints annotated stage output to stdout (or if no STAGE_NAME
# is set, just its arguments)
report() {
    if [[ -n "${STAGE_NAME:-}" ]]; then
        printf "  %s: %s\n" "${STAGE_NAME}" "$@"
    else
        printf "%s\n" "$@"
    fi
}

# prompt_default $1=default-value $2...=prompt
#   prompts the user and returns a default value if they provide no
#   reason
prompt_default() {
    local ANSWER
    local DEFAULT="$1"
    shift

    read -er -p "$* [${DEFAULT}]: " ANSWER
    if [ -z "${ANSWER}" ]; then
        ANSWER="${DEFAULT}"
    fi
    echo "${ANSWER}"
}

# prompt $1...=prompt
#   prompts the user and returns their response, which may be empty
prompt() {
    local ANSWER

    read -er -p "$*: " ANSWER
    echo "${ANSWER}"
}

# prompt_yesno $1...=prompt
#   prompts the user and returns their yes/no response
prompt_yesno() {
    local ANSWER

    read -er -p "$* (y/N): " ANSWER
    case "$(echo "${ANSWER}" | tr '[:lower:]' '[:upper:]')" in
        Y|YES)
            echo "Y"
            ;;
        *)
            echo "N"
            ;;
    esac
}

# prompt_pw $1...=prompt
#   prompts the user with terminal echo disabled and returns their
#   response, which may be empty
prompt_pw() {
    local ANSWER

    read -ers -p "$*: " ANSWER
    echo "${ANSWER}"
}

_SETUP_CONFIG_KEYS=()
_SETUP_CONFIG_VALUES=()
_SETUP_CONFIG_LOADED="false"

_write_config() {
    local FILE="${BDRPI_SETUP_CONFIG_FILE:-/boot/bdrpi-config.txt}"

    _load_config_once
    touch "${FILE}"

    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        local KEY="${_SETUP_CONFIG_KEYS[IDX]}"
        local VALUE="${_SETUP_CONFIG_VALUES[IDX]}"

        if [[ -z "${KEY}" ]]; then
            continue
        fi

        if grep -q -E "^${KEY}=" "${FILE}"; then
            sed -i '' "s/^${KEY}=.*/${KEY}=${VALUE}/" "${FILE}"
        else
            echo "${KEY}=${VALUE}" >>"${FILE}"
        fi
    done
}

_load_config() {
    local FILE="${BDRPI_SETUP_CONFIG_FILE:-/boot/bdrpi-config.txt}"

    _SETUP_CONFIG_KEYS=()
    _SETUP_CONFIG_VALUES=()

    if ! [[ -s "${FILE}" ]]; then
        # missing or empty is ok
        return 0
    fi

    local LINE
    while IFS= read -r LINE; do
        local KEY="${LINE%=*}"

        if [[ "${KEY}" =~ ^[[:space:]]*# ]] || [[ -z "${KEY}" ]]; then
            continue
        fi

        local VALUE="${LINE#"${KEY}"=}"
        _SETUP_CONFIG_KEYS+=("${KEY}")
        _SETUP_CONFIG_VALUES+=("${VALUE}")
    done < "${FILE}"
}

_load_config_once() {
    if ! "${_SETUP_CONFIG_LOADED}"; then
        _load_config
        _SETUP_CONFIG_LOADED="true"
    fi
}

# clear all values and reset to initial state
reset_setup_config() {
    _SETUP_CONFIG_LOADED="false"
    _SETUP_CONFIG_KEYS=()
    _SETUP_CONFIG_VALUES=()
}

# set config value: $1=param-name, $2=value
set_setup_config() {
    local KEY="${1:-}"
    local VALUE="${2:-}"

    [[ -z "${KEY}" ]] && abort "cannot set config with empty config key"

    _load_config_once

    local FOUND=false
    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        if [[ "${_SETUP_CONFIG_KEYS[IDX]}" == "${KEY}" ]]; then
            _SETUP_CONFIG_VALUES[IDX]="${VALUE}"
            FOUND=true
            break
        fi
    done

    if ! "${FOUND}"; then
        _SETUP_CONFIG_KEYS+=("${KEY}")
        _SETUP_CONFIG_VALUES+=("${VALUE}")
    fi

    _write_config || abort "failed to update config"
}

# clear config key & value: $1=param-name
clear_setup_config() {
    local KEY="${1:-}"

    [[ -z "${KEY}" ]] && abort "cannot clear config with empty config key"

    _load_config_once

    local FOUND="false"
    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        if [[ "${_SETUP_CONFIG_KEYS[IDX]}" == "${KEY}" ]]; then
            _SETUP_CONFIG_KEYS[IDX]=""
            _SETUP_CONFIG_VALUES[IDX]=""
            FOUND="true"
            break
        fi
    done

    if "${FOUND}"; then
        _write_config || abort "failed to update config"
    fi

    return 0
}

# get config value: $1=param-name
get_setup_config() {
    local KEY="${1:-}"

    [[ -z "${KEY}" ]] && abort "cannot get empty config key"

    _load_config_once

    local VALUE=""
    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        if [[ "${_SETUP_CONFIG_KEYS[IDX]}" == "${KEY}" ]]; then
            VALUE="${_SETUP_CONFIG_VALUES[IDX]}"
            break
        fi
    done

    echo "${VALUE}"
}

# set an array key: $1=array-name, $2=index or "append", $3=value
set_setup_config_array() {
    local KEY="${1:-}"
    local INDEX="${2:-}"
    local VALUE="${3:-}"

    [[ -z "${KEY}" ]] && abort "cannot set empty config array key"
    [[ -z "${INDEX}" ]] && abort "cannot set config array without index"

    _load_config_once

    local ARRAYKEY=""
    if [[ "${INDEX}" != "append" ]]; then
        ARRAYKEY="${KEY}.${INDEX}"
        local FOUND=false
        for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
            if [[ "${_SETUP_CONFIG_KEYS[IDX]}" == "${ARRAYKEY}" ]]; then
                FOUND=true
                break
            fi
        done

        "${FOUND}" || abort "unable to ${KEY}[${INDEX}] -- not found"
    else
        # append
        local NEXT_INDEX
        NEXT_INDEX="$(get_setup_config_array_size "${KEY}")"

        ARRAYKEY="${KEY}.${NEXT_INDEX}"
    fi

    [[ -n "${ARRAYKEY}" ]] || abort "internal error computing array value key"

    set_setup_config "${ARRAYKEY}" "${VALUE}"
}

# get an array key: $1=array-name, $2=index
get_setup_config_array() {
    local KEY="${1:-}"
    local INDEX="${2:-}"

    [[ -z "${KEY}" ]] && abort "cannot get with empty config array key"
    [[ -z "${INDEX}" ]] && abort "cannot get config array without index"

    _load_config_once

    local ARRAYKEY="${KEY}.${INDEX}"
    get_setup_config "${ARRAYKEY}"
}

# get an array's size: $1=array-name
get_setup_config_array_size() {
    local KEY="${1:-}"

    [[ -z "${KEY}" ]] && abort "cannot get size with empty config array key"

    _load_config_once

    local LAST_INDEX="-1"
    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        if [[ "${_SETUP_CONFIG_KEYS[IDX]}" =~ ^${KEY}\.([0-9]+) ]]; then
            local THIS_INDEX="${BASH_REMATCH[1]}"
            if [[ ${THIS_INDEX} -gt ${LAST_INDEX} ]]; then
                LAST_INDEX="${THIS_INDEX}"
            fi
        fi
    done

    let LAST_INDEX=LAST_INDEX+1
    echo "${LAST_INDEX}"
}

ROOT_DIR="$(cd "$(dirname "$0}")" && pwd)"

DRYRUN="false"

OSLIST_URL="https://downloads.raspberrypi.org/os_list_imagingutility_v4.json"

BDRPI_TMP="${TMPDIR:-/tmp}/bdr-pi-imager.$$"
CACHE_DIR="${HOME}/.bdr-pi-cache"

# print usage and quit
usage() {
    if [[ -n "$1" ]]; then
        perror "$@"
        perror ""
    fi
    grep "^#/#" "$0" | cut -c"5-" >&2
    exit 1
}

# make a file in our temp directory
tmpfile() {
    local name="${BDRPI_TMP}/${1:-tmp}"
    echo "${name}"
}
trap 'rm -rf "${BDRPI_TMP}"' EXIT

# list disks for imaging
list_disks() {
    declare -a TYPES=("external" "physical")

    while [[ -n "${1:-}" ]]; do
        case "$1" in
            -a|-all|--all)
                TYPES=()
                shift
                ;;
            *)
                usage "ERROR: list-disks: unknown flag $1"
                ;;
        esac
    done

    local PLIST="$(tmpfile disk-plist)"
    local TOTAL=0

    diskutil list -plist ${TYPES[@]:-} >"${PLIST}" || abort "error listing disks"

    local NUM_DISKS="$(plutil -extract AllDisksAndPartitions raw "${PLIST}")"
    if [[ "${NUM_DISKS}" -gt 0 ]]; then
        local INDEX
        for INDEX in $(jot "${NUM_DISKS}" 0); do
            local DISK="$( \
                  plutil \
                         -extract "AllDisksAndPartitions.${INDEX}.DeviceIdentifier" \
                         raw "${PLIST}" )"
            if [[ -z "${DISK}" ]]; then
                continue
            fi

            local VOLUME="$( \
                  plutil \
                         -extract "AllDisksAndPartitions.${INDEX}.Partitions.0.MountPoint" \
                         raw "${PLIST}" )"

            echo "/dev/${DISK}  ${VOLUME:-?}"
            let TOTAL=TOTAL+1
        done
    fi

    if [[ "${TOTAL}" -eq 0 ]]; then
        echo "No disks found."
    fi

    return 0
}

# download a resource $1=URL $2=sha256 (or omit for no checks)
download_resource() {
    local IMAGEURL="${1:-}"
    local HASH="${2:-}"

    if [[ -z "${IMAGEURL}" ]]; then
        abort "internal error: no image url"
    fi

    local FILE="$(basename "${IMAGEURL}")"
    local CACHE_FILE="${CACHE_DIR}/${FILE}"

    if [[ -f "${CACHE_FILE}" ]]; then
        echo "Using cached file ${CACHE_FILE}" >/dev/stderr
    else
        echo "Downloading ${IMAGEURL}..." >/dev/stderr

        curl --progress-bar --output "${CACHE_FILE}" "${IMAGEURL}" || \
            abort "failed to download ${IMAGEURL}"
    fi

    if [[ -n "${HASH}" ]]; then
        echo "Validating file..." >/dev/stderr

        local FILE="$(prep_image "${CACHE_FILE}")"
        local FILEHASH="$(shasum -a 256 "${FILE}" | awk '{print $1}')"

        [[ "${FILEHASH}" == "${HASH}" ]] || abort "hash mismatch got ${FILEHASH}, expected ${HASH}"

        echo "ok" >/dev/stderr
    fi

    echo "${CACHE_FILE}"
}

# get a list of images via OSLIST_URL
get_images() {
    local OSLIST
    OSLIST="$(download_resource "${OSLIST_URL}")"
    [[ -z "{OSLIST}" ]] && exit 1

    local FILTERED_OSLIST="$(tmpfile oslist-filtered-json)"

    # Get the top-level images.
    {
        jq '.os_list' "${OSLIST}" | \
            jq '.[] | select(.devices // [] | contains(["pi4-64bit"])) | {"name":.name, "url":.url, "sha":.extract_sha256}' | \
            jq 'select(.url != null)' >"${FILTERED_OSLIST}"
    } || abort "failed to perform first filter pass on os list"

    # Get nested images.
    {
        jq '.os_list' "${OSLIST}" | \
            jq '.[] | (.subitems // [])[] | select(.devices // [] | contains(["pi4-64bit"])) | {"name":.name, "url":.url, "sha":.extract_sha256}' | \
            jq 'select(.url != null)' >>"${FILTERED_OSLIST}"
    } || abort "failed to perform second filter pass on os list"

    echo "${FILTERED_OSLIST}"
}

# print a list of images
list_images() {
    local IMAGELIST="$(get_images "$@")"
    [[ -z "${IMAGELIST}" ]] && return 1

    jq -r '.name + "\n\t" + .url + "\n"' "${IMAGELIST}"

    return 0
}

# if the file is compressed, decompress it and return a path to the decompressed file,
# otherwise just returns the file
prep_image() {
    IMAGE="${1}"

    if [[ "${IMAGE}" = *.xz ]]; then
        local BASE="$(basename "${IMAGE}")"
        local RESULT="$(tmpfile "${BASE/%\.xz/}")"
        if [[ ! -f "${RESULT}" ]]; then
            xz --decompress --stdout --thread=0 "${IMAGE}" > "${RESULT}"
        fi
        echo "${RESULT}"
    else
        echo "${IMAGE}"
    fi
}

# prompt the user to select an image to use
select_image() {
    local IMAGELIST="$(get_images "$@")"
    [[ -z "${IMAGELIST}" ]] && exit 1

    jq -r '.name' "${IMAGELIST}" | nl -s $'.\t' >/dev/stderr || abort "couldn't print the list"

    local DEFAULT="$(
        jq -r '.name' "${IMAGELIST}" | \
        nl -s: -w1 | \
        grep Legacy | grep 64-bit | grep Lite |\
        cut -d: -f1)"

    local PICK
    if [[ -n "${DEFAULT}" ]]; then
        PICK="$(prompt_default "${DEFAULT}" "Select a base image")"
    else
        PICK="$(prompt "Select a base image")"
    fi
    [[ -n "${PICK}" ]] || abort "no image selected"

    local IMAGEURL="$(
        jq -r '.url' "${IMAGELIST}" | \
        nl -s: -w1 | \
        grep -E "^${PICK}:" |\
        cut -d: -f2-)"
    [[ -n "${IMAGEURL}" ]] || abort "no valid image selected"

    local IMAGEHASH="$(
        jq -r '.sha' "${IMAGELIST}" | \
        nl -s: -w1 | \
        grep -E "^${PICK}:" |\
        cut -d: -f2-)"

    local IMAGE="$(download_resource "${IMAGEURL}" "${IMAGEHASH}")"
    [[ -z "${IMAGE}" ]] && exit 1

    echo "${IMAGE}"
}

# query use about configuring wifi
set_wifi_config() {
    local FIRST=true
    local ADD_WIFI
    while true; do
        echo >/dev/stderr

        if "${FIRST}"; then
            ADD_WIFI="$(prompt_yesno "Pre-configure wifi for post-boot configuration?")"
            FIRST=false
        else
            ADD_WIFI="$(prompt_yesno "Pre-configure another wifi network?")"
        fi

        if [[ "${ADD_WIFI}" != "Y" ]]; then
            break
        fi

        SSID="$(prompt "Enter an SSID")"
        PASS="$(prompt_pw "Enter a password for ${SSID}")"

        [[ -n "${SSID}" ]] && [[ -n "${PASS}" ]] || abort "network config requires both an SSID and password"

        set_setup_config_array WIFI_SSID append "${SSID}"
        set_setup_config_array WIFI_PASS append "${PASS}"
    done

    echo >/dev/stderr

    ADD_WIFI="$(prompt_yesno "Prompt for additional networks during post-boot configuration?")"
    if [[ "${ADD_WIFI}" == "Y" ]]; then
        set_setup_config WIFI_PERFORM_SSID_SETUP "true"
    else
        set_setup_config WIFI_PERFORM_SSID_SETUP "false"
    fi
    echo >/dev/stderr
}

set_lifepo4wered_config() {
    local CONFIG_LIFEPO

    CONFIG_LIFEPO="$(prompt_yesno "Configure lifepo4wered-pi UPS software during post-boot configuration?")"
    if [[ "${CONFIG_LIFEPO}" == "Y" ]]; then
        set_setup_config LIFEPO_PERFORM_SETUP "true"
    else
        set_setup_config LIFEPO_PERFORM_SETUP "false"
    fi
}

# prepare and write an image to the given $1=disk
image() {
    local DISK="${1:-}"
    if [[ -z "${DISK}" ]]; then
        usage "ERROR: image: missing disk name argument"
    fi

    local SAFE=""
    local DRYRUN_NO_DISK="false"
    if "${DRYRUN}"; then
        echo "Dry-run mode enabled."
        SAFE="echo"

        if ! [[ -e "${DISK}" ]]; then
            DRYRUN_NO_DISK="true"
        fi
    fi

    local IMAGE="$(select_image)"
    [[ -z "${IMAGE}" ]] && exit 1

    echo
    echo "Inspecting disk..."
    local BLOCKSIZE
    if "${DRYRUN_NO_DISK}"; then
        # TODO: bash math fails on this disk size
        echo "No Disk: setting arbitrary dry-run volume size of 512000000000"
        SIZE="512000000000"
        echo "No Disk: Setting aribitrary dry-run block size of 512"
        BLOCKSIZE="512"
    else
        local PLIST="$(tmpfile disk-plist)"
        diskutil info -plist "${DISK}" >"${PLIST}" || abort "error getting disk info"

        local SIZE="$(plutil -extract "Size" raw "${PLIST}")"
        if [[ -z "${SIZE}" ]]; then
            abort "failed to determine disk size"
        fi
        if [[ "${SIZE}" -lt 32000000000 ]]; then
            abort "volume is less than 32 GiB... giving up"
        fi
        local SIZE_GB
        let SIZE_GB=SIZE/1000000000

        echo "Volume size is approximately ${SIZE_GB} GiB (${SIZE})."

        BLOCKSIZE="$(plutil -extract "DeviceBlockSize" raw "${PLIST}")"
        if [[ -z "${BLOCKSIZE}" ]] || [[ "${BLOCKSIZE}" -eq 0 ]]; then
            abort "cannot determine block size"
        fi
        echo "Block size is ${BLOCKSIZE}."
    fi

    # rewrite /dev/diskX to /dev/rdiskX
    RDISK="${DISK//\/dev\/disk//dev/rdisk}"

    # format the disk
    echo
    echo "Formatting disk..."
    ${SAFE} sudo diskutil eraseDisk FAT32 "BDR_PI" MBRFormat "${DISK}" || \
        abort "format operation failed"

    # unmount the disk
    echo
    echo "Preparing disk..."
    ${SAFE} diskutil unmountDisk "${DISK}" || abort "failed to unmount disk"

    # zero first MB
    let NBLKS=(1024*1024 / BLOCKSIZE)
    ${SAFE} sudo dd bs="${BLOCKSIZE}" count="${NBLKS}" \
            if=/dev/zero \
            of="${RDISK}" \
            status=none || abort "failed to zero first MB"

    # zero last MB
    let SIZE_BLKS=(SIZE / 512)
    let SBLKS=(SIZE_BLKS - NBLKS)
    ${SAFE} sudo dd bs="${BLOCKSIZE}" oseek="${SBLKS}" count="${NBLKS}" \
            if=/dev/zero \
            of="${RDISK}" \
            status=none || abort "failed to zero last MB"


    echo
    echo "Writing image... (this could take a while)"

    # Write the image. rpi-imager skips the first 4kb and then writes
    # it last. Not sure why.
    ${SAFE} sudo dd bs=1m if="$(prep_image "${IMAGE}")" of="${RDISK}" status=progress

    echo "...done"

    echo
    echo "Mounting disk for post-image tweaks..."
    # remount the disk
    ${SAFE} diskutil mountDisk "${DISK}" || abort "failed to re-mount disk"

    local VOLUME
    if "${DRYRUN}"; then
        # Pretend /tmp is our volume.
        VOLUME="/tmp/example-boot-volume"
        mkdir -p "${VOLUME}" || abort "error creating ${VOLUME} for dry-run"
    else
        # Figure out the volume name of our disk (which is set by the image), and where it lives
        VOLUME="$(list_disks | grep -F "${DISK}" | awk '{print $2}')"

        [[ -n "${VOLUME}" ]] || abort "could not find volume for ${DISK}"
    fi

    export BDRPI_SETUP_CONFIG_FILE="${VOLUME}/bdrpi-config.txt"
    echo
    echo "Writing setup config to ${BDRPI_SETUP_CONFIG_FILE}"

    set_wifi_config
    set_lifepo4wered_config

    cp "${ROOT_DIR}/resources/firstrun.sh" "${VOLUME}/bdrpi-firstrun.sh"
    cp "${ROOT_DIR}/docs/setup.sh" "${VOLUME}/bdrpi-setup.sh"

    if [[ -f "${VOLUME}/cmdline.txt" ]]; then
        local CMDLINE="$(cat "${VOLUME}/cmdline.txt")"
        CMDLINE="${CMDLINE} systemd.run=/boot/bdrpi-firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target"
        ${SAFE} echo "${CMDLINE}" >"${VOLUME}/cmdline.txt" || abort "unable to write ${VOLUME}/cmdline.txt"
    fi

    echo
    echo "Ejecting ${DISK}..."

    ${SAFE} diskutil eject "${DISK}" || \
        abort "failed to eject ${DISK}, but I think I'm done..."

    echo "Done!"

    return 0
}

clear_cache() {
    local SAFE=""
    if "${DRYRUN}"; then
        echo "Dry-run mode enabled."
        SAFE="echo"
    fi

    ${SAFE} rm -rf "${CACHE_DIR}"
}

# Require bash
# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]; then
    abort "bash is required to interpret this script."
fi

# Currently we only support macOS for imaging SD cards.
OS="$(uname)"
if [[ "$OS" != "Darwin" ]]; then
    abort "OS is ${OS} -- this isn't going to work out."
fi

# These should just exist on macOS
for TOOL in awk curl diskutil jot plutil shasum; do
    if ! installed "${TOOL}"; then
        abort "could not find ${TOOL}, is this macOS?"
    fi
done

for TOOL in jq xz; do
    if ! installed "${TOOL}"; then
        abort "could not find ${TOOL}, please install (homebrew works)"
    fi
done

mkdir -p "${BDRPI_TMP}" || abort "failed to create temp dir"
mkdir -p "${CACHE_DIR}" || abort "failed to create image cache dir"

while [[ -n "${1:-}" ]]; do
    case "$1" in
        -n|-dry-run|--dry-run)
            DRYRUN=true
            shift
            ;;

        clear-cache)
            shift
            clear_cache "$@"
            exit $?
            ;;

        list-disks)
            shift
            list_disks "$@"
            exit $?
            ;;

        list-images)
            shift
            list_images "$@"
            exit $?
            ;;

        image)
            shift
            image "$@"
            exit $?
            ;;
        *)
            usage "ERROR: unknown command: $1"
            ;;
    esac
done

usage "ERROR: no command given"
