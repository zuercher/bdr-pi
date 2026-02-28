#!/bin/bash
# shellcheck disable=SC2317

#/# Usage: imager.sh <command> <options>
#/#
#/# Options:
#/#     -n, --dry-run
#/#         Skip actual work in the image command.
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
    printf "%s\n" "$*" >/dev/stderr
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
        printf "  %s: %s\n" "${STAGE_NAME}" "$*"
    else
        printf "%s\n" "$*"
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

# prompt_yesno $1=default $2...=prompt
#   prompts the user and returns their yes/no response
prompt_yesno() {
    local ANSWER DEAFULT DEFAULT_DESC

    DEFAULT="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
    shift

    case "${DEFAULT}" in
        Y|YES)
            DEFAULT_DESC="Y"
            ;;
        *)
            DEFAULT_DESC="N"
            ;;
    esac

    read -er -p "$* [${DEFAULT_DESC}]: " ANSWER
    if [[ -z "${ANSWER}" ]]; then
        ANSWER="${DEFAULT}"
    fi
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

# sed_inplace ...
#   runs sed with the given arguments and the appropriate "edit
#   in-place, no backup" flag for the OS. Mostly so we can test
#   on macOS.
sed_inplace() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

_SETUP_CONFIG_KEYS=()
_SETUP_CONFIG_VALUES=()
_SETUP_CONFIG_LOADED="false"

_debug() {
    true || perror "$@"
}

_write_config() {
    local FILE="${BDRPI_SETUP_CONFIG_FILE}"
    [[ -n "${FILE}" ]] || abort "BDR_SETUP_CONFIG_FILE not set"

    _load_config_once

    _debug "save config to ${FILE}"

    rm -f "${FILE}"
    touch "${FILE}"

    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        local KEY="${_SETUP_CONFIG_KEYS[IDX]}"
        local VALUE="${_SETUP_CONFIG_VALUES[IDX]}"

        echo "${KEY}=${VALUE}" >>"${FILE}"
    done
}

_load_config() {
    local FILE="${BDRPI_SETUP_CONFIG_FILE}"
    [[ -n "${FILE}" ]] || abort "BDR_SETUP_CONFIG_FILE not set"

    _debug "loading config from ${FILE}"

    _SETUP_CONFIG_KEYS=()
    _SETUP_CONFIG_VALUES=()

    if ! [[ -s "${FILE}" ]]; then
        # missing or empty is ok
        _debug "loaded empty config from ${FILE}"
        return 0
    fi

    local N=0
    local LINE
    while IFS= read -r LINE; do
        local KEY="${LINE%=*}"

        if [[ "${KEY}" =~ ^[[:space:]]*# ]] || [[ -z "${KEY}" ]]; then
            continue
        fi

        local VALUE="${LINE#"${KEY}"=}"
        _SETUP_CONFIG_KEYS+=("${KEY}")
        _SETUP_CONFIG_VALUES+=("${VALUE}")

        N=$((N + 1))
    done < "${FILE}"

    _debug "loaded ${N} config entries from ${FILE}"
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

    LAST_INDEX=$((LAST_INDEX+1))
    echo "${LAST_INDEX}"
}

# clear an array: $1=array-name
clear_setup_config_array() {
    local KEY="${1:-}"

    [[ -z "${KEY}" ]] && abort "cannot clear config with empty config array key"

    _load_config_once

    local FOUND="false"
    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        if [[ "${_SETUP_CONFIG_KEYS[IDX]}" =~ ^${KEY}\.[0-9]+ ]]; then
            _SETUP_CONFIG_KEYS[IDX]=""
            _SETUP_CONFIG_VALUES[IDX]=""
            FOUND="true"
        fi
    done

    if "${FOUND}"; then
        _write_config || abort "failed to update config"

        # easier than mangling arrays
        reset_setup_config
    fi
}

_config_txt() {
    echo "${BDRPI_BOOT_CONFIG_TXT:-/boot/config.txt}"
}

# boot_config_contains_regex $1=section $2=regex returns success if
# /boot/config.txt contains a line matching regex within section
# marked by [section].
boot_config_contains_regex() {
    local SECTION="$1"
    local REGEX="$2"

    local MATCHING
    MATCHING="$(
        awk -v S="[${SECTION}]" \
            -v C='[all]' \
            '{
               if (substr($0, 0, 1) == "[") { C = $0 }
               else if (C == S) { print $0 }
             }' \
             "$(_config_txt)" | \
        grep -E "${REGEX}"
    )"

    [[ -n "${MATCHING}" ]]
}

# boot_config_contains $1=section $2=key $3=[value] checks if the
# /boot/config.txt contains the give key (or key=value) entry in the
# named section.
boot_config_contains() {
    local SECTION="$1"
    local KEY="$2"
    local VALUE=""
    if [[ $# -gt 2 ]]; then
        VALUE="$3"
    fi

    boot_config_contains_regex "${SECTION}" "^${KEY}=${VALUE}"
}

# boot_config_printf $1=section $...=printf-args checks if the last
# section in /boot/config.txt matches the given section. If not, it
# adds the section to the config. In any case, the remaining args are
# used with printf to adds lines to the config. Schedules a reboot on
# successful change.
boot_config_printf() {
    local SECTION="$1"
    shift

    local CONFIG_TXT="$(_config_txt)"
    touch "${CONFIG_TXT}"

    local LAST_SECTION
    LAST_SECTION="$(grep -E '^\[' "${CONFIG_TXT}" | tail -n 1)"
    if [[ "${LAST_SECTION}" != "[${SECTION}]" ]]; then
        printf "\n[%s]\n" "${SECTION}" >>"$(_config_txt)" || \
            abort "failed to add section ${SECTION} to ${CONFIG_TXT}"
    fi

    # shellcheck disable=SC2059
    printf "$@" >>"${CONFIG_TXT}" || abort "failed to append ${SECTION} to ${CONFIG_TXT}"

    reboot_required
}

# boot_config_replace $1=section $2=key $3=value sets the key to value
# in the given section of /boot/config.txt. Fails if the key is not
# already present in the section. Schedules a reboot on successful
# change.
boot_config_replace() {
    local SECTION="$1"
    local KEY="$2"
    local VALUE="$3"

    local CONFIG BACKUP
    CONFIG="$(_config_txt)"
    BACKUP="$(_config_txt)~"

    if awk -v S="[${SECTION}]" \
           -v C='[all]' \
           -v K="${KEY}" \
           -v V="${VALUE}" \
           -v EC="1" \
           '{
              if (substr($0, 0, 1) == "[") {
                C = $0
                print $0
              } else if (C == S) {
                if (match($0, "^#?" K "=")) {
                  print K "=" V
                  EC = 0
                } else {
                  print $0
                }
              } else {
                print $0
              }
           }
           END { exit EC }' \
           "${CONFIG}" >"${BACKUP}"; then
        if mv "${BACKUP}" "${CONFIG}"; then
            reboot_required
            return 0
        fi
    fi

    abort "failed to replace key ${KEY} with ${VALUE} in section ${SECTION}"
}

# boot_config_set $1=section $2=key $3=value sets the key to value in
# the given section of /boot/config.txt. If the key does not exist in
# the given section, it is appended. Schedules a reboot if the file is
# changed.
boot_config_set() {
    local SECTION="$1"
    local KEY="$2"
    local VALUE="$3"

    if boot_config_contains "${SECTION}" "${KEY}" "${VALUE}"; then
        # Already set.
        report "boot config: ${KEY} already set to ${VALUE} in section ${SECTION}"
        return 0
    fi

    report "boot config: setting ${KEY} to ${VALUE} in section ${SECTION}"

    if boot_config_contains_regex "${SECTION}" "^#?${KEY}="; then
        # Has value, possibly commented out.
        boot_config_replace "${SECTION}" "${KEY}" "${VALUE}"
    else
        # No value, append it.
        boot_config_printf "${SECTION}" "%s=%s\n\n" "${KEY}" "${VALUE}"
    fi
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

    local PLIST TOTAL NUM_DISKS
    PLIST="$(tmpfile disk-plist)"
    TOTAL=0

    # shellcheck disable=SC2068
    diskutil list -plist ${TYPES[@]:-} >"${PLIST}" || abort "error listing disks"

    NUM_DISKS="$(plutil -extract AllDisksAndPartitions raw "${PLIST}")"
    if [[ "${NUM_DISKS}" -gt 0 ]]; then
        local INDEX
        for INDEX in $(jot "${NUM_DISKS}" 0); do
            local DISK VOLUME
            DISK="$( \
                  plutil \
                         -extract "AllDisksAndPartitions.${INDEX}.DeviceIdentifier" \
                         raw "${PLIST}" )"
            if [[ -z "${DISK}" ]]; then
                continue
            fi

            VOLUME="$( \
                  plutil \
                         -extract "AllDisksAndPartitions.${INDEX}.Partitions.0.MountPoint" \
                         raw "${PLIST}" )"

            echo "/dev/${DISK}: ${VOLUME:-?}"
            TOTAL=$((TOTAL+1))
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

    local FILE
    FILE="$(basename "${IMAGEURL}")"
    local CACHE_FILE="${CACHE_DIR}/${FILE}"

    if [[ -f "${CACHE_FILE}" ]]; then
        perror "Using cached file ${CACHE_FILE}"
    else
        perror "Downloading ${IMAGEURL}..."

        curl --progress-bar --output "${CACHE_FILE}" "${IMAGEURL}" || \
            abort "failed to download ${IMAGEURL}"
    fi

    local FINAL_CACHE_FILE="${CACHE_FILE}"
    if [[ "${CACHE_FILE}" = *.xz ]]; then
        FINAL_CACHE_FILE="${CACHE_FILE/%\.xz/}"

        if [[ -f "${FINAL_CACHE_FILE}" ]]; then
            perror "Using cached uncompressed file ${FINAL_CACHE_FILE}"
        else
            perror "Decompressing ${CACHE_FILE}"
            xz --decompress --stdout --thread=0 "${CACHE_FILE}" > "${FINAL_CACHE_FILE}"
        fi
    fi

    if [[ -n "${HASH}" ]]; then
        perror "Validating ${FINAL_CACHE_FILE}..."

        local FILEHASH
        FILEHASH="$(shasum -a 256 "${FINAL_CACHE_FILE}" | awk '{print $1}')"

        [[ "${FILEHASH}" == "${HASH}" ]] || abort "hash mismatch got ${FILEHASH}, expected ${HASH}"

        perror "ok"
    fi

    echo "${FINAL_CACHE_FILE}"
}

# get a list of images via OSLIST_URL
get_images() {
    local OSLIST FILTERED_OSLIST
    OSLIST="$(download_resource "${OSLIST_URL}")"
    [[ -z "${OSLIST}" ]] && exit 1

    FILTERED_OSLIST="$(tmpfile oslist-filtered-json)"

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
    local IMAGELIST
    IMAGELIST="$(get_images "$@")"
    [[ -z "${IMAGELIST}" ]] && return 1

    jq -r '.name + "\n\t" + .url + "\n"' "${IMAGELIST}"

    return 0
}

# prompt the user to select an image to use
select_image() {
    local IMAGELIST
    IMAGELIST="$(get_images "$@")"
    [[ -z "${IMAGELIST}" ]] && exit 1

    jq -r '.name' "${IMAGELIST}" | nl -s $'.\t' >/dev/stderr || abort "couldn't print the list"

    local DEFAULT PICK IMAGEURL IMAGEHASH IMAGE
    DEFAULT="$(
        jq -r '.name' "${IMAGELIST}" | \
        nl -s: -w1 | \
        grep -v Legacy | grep 64-bit | grep Lite |\
        cut -d: -f1)"

    if [[ -n "${DEFAULT}" ]]; then
        PICK="$(prompt_default "${DEFAULT}" "Select a base image (probably want Lite)")"
    else
        PICK="$(prompt "Select a base image")"
    fi
    [[ -n "${PICK}" ]] || abort "no image selected"

    IMAGEURL="$(
        jq -r '.url' "${IMAGELIST}" | \
        nl -s: -w1 | \
        grep -E "^${PICK}:" |\
        cut -d: -f2-)"
    [[ -n "${IMAGEURL}" ]] || abort "no valid image selected"

    IMAGEHASH="$(
        jq -r '.sha' "${IMAGELIST}" | \
        nl -s: -w1 | \
        grep -E "^${PICK}:" |\
        cut -d: -f2-)"

    IMAGE="$(download_resource "${IMAGEURL}" "${IMAGEHASH}")"
    [[ -z "${IMAGE}" ]] && exit 1

    echo "${IMAGE}"
}

# query use about configuring wifi
set_wifi_config() {
    local WIFI_COUNTRY
    WIFI_COUNTRY="$(prompt_default US "Specify wifi country code")"

    if [[ "${WIFI_COUNTRY}" =~ ^[A-Z][A-Z]$ ]]; then
        echo "Wifi country code: ${WIFI_COUNTRY}"
        set_setup_config WIFI_COUNTRY "${WIFI_COUNTRY}"
    else
        abort "Wifi country must be a two-digit country identifier (e.g. US or GB)"
    fi

    local NUM=0
    local ADD_WIFI
    while true; do
        perror

        if [[ "${NUM}" -eq 0 ]]; then
            perror "Preconfiguring a wifi network allows bdr-pi configuration to proceed"
            perror "on first boot without user intervention."

            ADD_WIFI="$(prompt_yesno Y "Pre-configure wifi?")"
        else
            if [[ "${NUM}" -eq 1 ]]; then
                perror "Preconfiguring additional wifi networks (e.g. the pepwave) allows bdr-pi"
                perror "configuration to proceed with zero intervention."
            fi

            ADD_WIFI="$(prompt_yesno N "Pre-configure another wifi network?")"
        fi

        if [[ "${ADD_WIFI}" != "Y" ]]; then
            break
        fi
        NUM=$((NUM+1))

        local SSID PASS PASS_AGAIN
        while true; do
            SSID="$(prompt "Enter an SSID")"
            PASS="$(prompt_pw "Enter a password for ${SSID}")"
            echo

            PASS_AGAIN="$(prompt_pw "Re-enter password for ${SSID}")"
            echo
            if [[ "${PASS}" == "${PASS_AGAIN}" ]]; then
                break
            fi

            echo "Passwords didn't match, let's try again."
            echo
        done

        if [[ -z "${SSID}" ]] || [[ -z "${PASS}" ]]; then
            abort "network config requires both an SSID and password"
        fi
        HIGH_PRIO="$(prompt_yesno N "Make ${SSID} preferred?")"

        set_setup_config_array WIFI_SSID append "${SSID}"
        set_setup_config_array WIFI_PASS append "${PASS}"

        if [[ "${HIGH_PRIO}" == "Y" ]]; then
            set_setup_config_array WIFI_PRIO append 10
        else
            set_setup_config_array WIFI_PRIO append 0
        fi
    done

    perror

    ADD_WIFI="$(prompt_yesno Y "Skip querying for additional networks during post-boot configuration?")"
    if [[ "${ADD_WIFI}" == "Y" ]]; then
        set_setup_config WIFI_PERFORM_SSID_SETUP "false"
    else
        set_setup_config WIFI_PERFORM_SSID_SETUP "true"
    fi
}

set_lifepo4wered_config() {
    local CONFIG_LIFEPO

    perror "Configuring lifepo4wered-pi requires the hardware be present."
    perror "(Power the Raspberry Pi directly via USB for install.)"

    CONFIG_LIFEPO="$(prompt_yesno Y "Configure lifepo4wered-pi UPS software during post-boot configuration?")"
    if [[ "${CONFIG_LIFEPO}" == "Y" ]]; then
        set_setup_config LIFEPO_PERFORM_SETUP "true"
    else
        set_setup_config LIFEPO_PERFORM_SETUP "false"
    fi
}

set_user_config() {
    local USER PASS PASS_AGAIN

    perror "User configuration. Password is temporarily stored in the image."

    USER="$(prompt_default "pi" "Select a username")"
    [[ -n "${USER}" ]] || abort "must select a username"

    while true; do
        PASS="$(prompt_pw "Password")"
        echo
        [[ -n "${PASS}" ]] || abort "must select a password"

        PASS_AGAIN="$(prompt_pw "Re-enter password")"
        echo
        if [[ "${PASS}" == "${PASS_AGAIN}" ]]; then
            break
        fi

        echo
        echo "Passwords did not match. Please try again."
        echo
    done

    set_setup_config FIRST_RUN_USER "${USER}"
    set_setup_config FIRST_RUN_PASS "${PASS}"
}

set_rotate_display() {
    local ROTATE

    ROTATE=$(prompt_yesno N "Rotate display 180 degress?")
    if [[ "${ROTATE}" == "Y" ]]; then
        set_setup_config DISPLAY_ROTATE 180
    fi
}

set_autolaunch_racecapture() {
    local AUTOLAUNCH

    AUTOLAUNCH=$(prompt_yesno Y "Automatically launch racecapture on login?")
    if [[ "${AUTOLAUNCH}" == "N" ]]; then
        set_setup_config RACECAPTURE_AUTOLAUNCH false
    else
        set_setup_config RACECAPTURE_AUTOLAUNCH true
    fi
}

# Provide an implementation so that lib/boot_config.sh
# can find it, but because we're imaging there's no
# actual reboot necessary.
reboot_required() {
    true
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
        perror "Dry-run mode enabled."
        SAFE="echo"

        if ! [[ -e "${DISK}" ]]; then
            DRYRUN_NO_DISK="true"
        fi
    fi

    local IMAGE
    IMAGE="$(select_image)"
    [[ -z "${IMAGE}" ]] && exit 1

    perror
    perror "Inspecting disk..."
    local SIZE BLOCKSIZE
    if "${DRYRUN_NO_DISK}"; then
        # TODO: bash math fails on this disk size
        perror "No Disk: setting arbitrary dry-run volume size of 512000000000"
        SIZE="512000000000"
        perror "No Disk: Setting aribitrary dry-run block size of 512"
        BLOCKSIZE="512"
    else
        local PLIST
        PLIST="$(tmpfile disk-plist)"
        diskutil info -plist "${DISK}" >"${PLIST}" || abort "error getting disk info"

        local DEVICE_NODE
        DEVICE_NODE="$(plutil -extract "DeviceNode" raw "${PLIST}")"
        if [[ "${DEVICE_NODE}" != "${DISK}" ]]; then
            abort "Disk ${DISK} is not the root device, did you give the mount path?"
        fi

        SIZE="$(plutil -extract "Size" raw "${PLIST}")"
        if [[ -z "${SIZE}" ]]; then
            abort "failed to determine disk size"
        fi
        if [[ "${SIZE}" -lt 32000000000 ]]; then
            abort "volume is less than 32 GiB... giving up"
        fi
        local SIZE_GB=$((SIZE/1000000000))

        perror "Volume size is approximately ${SIZE_GB} GiB (${SIZE})."

        BLOCKSIZE="$(plutil -extract "DeviceBlockSize" raw "${PLIST}")"
        if [[ -z "${BLOCKSIZE}" ]] || [[ "${BLOCKSIZE}" -eq 0 ]]; then
            abort "cannot determine block size"
        fi
        perror "Block size is ${BLOCKSIZE}."
    fi

    # rewrite /dev/diskX to /dev/rdiskX
    local RDISK
    RDISK="${DISK//\/dev\/disk//dev/rdisk}"

    # format the disk
    perror
    perror "Formatting disk..."
    perror "  (This uses sudo and may ask for your password.)"
    ${SAFE} sudo diskutil eraseDisk FAT32 "BDR_PI" MBRFormat "${DISK}" || \
        abort "format operation failed"

    # unmount the disk
    perror
    perror "Preparing disk..."
    ${SAFE} diskutil unmountDisk "${DISK}" || abort "failed to unmount disk"

    # zero first MB
    local NBLKS=$((1024*1024 / BLOCKSIZE))
    ${SAFE} sudo dd bs="${BLOCKSIZE}" count="${NBLKS}" \
            if=/dev/zero \
            of="${RDISK}" \
            status=none || abort "failed to zero first MB"

    # zero last MB
    local SIZE_BLKS=$((SIZE / 512))
    local SBLKS=$((SIZE_BLKS - NBLKS))
    ${SAFE} sudo dd bs="${BLOCKSIZE}" oseek="${SBLKS}" count="${NBLKS}" \
            if=/dev/zero \
            of="${RDISK}" \
            status=none || abort "failed to zero last MB"

    perror
    perror "Writing image... (this could take a while)"

    # Write the image. rpi-imager skips the first 4kb and then writes
    # it last. Not sure why.
    ${SAFE} sudo dd bs=1m if="${IMAGE}" of="${RDISK}" status=progress

    perror "...done"

    perror
    perror "Mounting disk for post-image tweaks..."
    # remount the disk
    ${SAFE} diskutil mountDisk "${DISK}" || abort "failed to re-mount disk"

    local VOLUME
    if "${DRYRUN}"; then
        # Pretend /tmp is our volume.
        VOLUME="/tmp/example-boot-volume"
        mkdir -p "${VOLUME}" || abort "error creating ${VOLUME} for dry-run"
        touch "${VOLUME}/config.txt"
    else
        # Figure out the volume name of our disk (which is set by the image), and where it lives
        VOLUME="$(list_disks | grep -F "${DISK}" | awk '{print $2}')"

        [[ -n "${VOLUME}" ]] || abort "could not find volume for ${DISK}"
    fi

    export BDRPI_SETUP_CONFIG_FILE="${VOLUME}/bdr-pi-config.txt"
    perror
    perror "Writing setup config to ${BDRPI_SETUP_CONFIG_FILE}"

    set_user_config
    perror
    set_wifi_config
    perror
    set_lifepo4wered_config
    perror
    set_rotate_display
    perror
    set_autolaunch_racecapture

    # generate user-data
    local PI_HOSTNAME="$(prompt_default bdrpi "Specify a host name")"
    local FIRST_RUN_USER="$(get_setup_config FIRST_RUN_USER)"
    local FIRST_RUN_PASS="$(get_setup_config FIRST_RUN_PASS)"

    if ! sed -e "s/{{PI_HOSTNAME}}/${PI_HOSTNAME}/; s/{{FIRST_RUN_USER}}/${FIRST_RUN_USER}/; s/{{FIRST_RUN_PASS}}/${FIRST_RUN_PASS}/" "${ROOT_DIR}/resources/user-data.tmpl" >"${VOLUME}/user-data"; then
        abort "failed to write user-data to ${VOLUME}/user-data"
    fi

    # keep the user so we configure auto login
    clear_setup_config FIRST_RUN_PASS

    # generate_network-config
    local WIFI_COUNTRY="$(get_setup_config WIFI_COUNTRY)"

    if ! sed -e "s/{{WIFI_COUNTRY}}/${WIFI_COUNTRY}/" "${ROOT_DIR}/resources/network-config.tmpl" >"${VOLUME}/network-config"; then
        abort "failed to write network-config"
    fi

    local NUM_CONFIGS="$(get_setup_config_array_size WIFI_SSID)"
    if [[ -n "${NUM_CONFIGS}" ]] && [[ "${NUM_CONFIGS}" -gt 0 ]]; then
        local IDX=0
        while [[ "${IDX}" -lt "${NUM_CONFIGS}" ]]; do
            local SSID PASS
            SSID="$(get_setup_config_array WIFI_SSID "${IDX}")"
            PASS="$(get_setup_config_array WIFI_PASS "${IDX}")"

            if ! sed -e "s/{{SSID}}/${SSID}/; s/{{PASSWORD}}/${PASS}/" "${ROOT_DIR}/resources/network-config-ap.tmpl" >>"${VOLUME}/network-config"; then
                abort "failed to add wifi network to network-config"
            fi
            IDX=$((IDX+1))
        done

        clear_setup_config_array WIFI_SSID
        clear_setup_config_array WIFI_PASS
        clear_setup_config_array WIFI_PRIO
    fi

    # modify config.txt
    export BDRPI_BOOT_CONFIG_TXT="${VOLUME}/config.txt"

    boot_config_set "all" "dtparam=i2c_arm" "on"
    boot_config_set "all" "dtparam=audio" "off"
    boot_config_set "all" "diable_splash" "1"
    boot_config_set "all" "diable_touchscreen" "1"
    boot_config_set "all" "gpu_mem" "${BDRPI_GPU_MEM:-256}"

    cp "${ROOT_DIR}/resources/firstrun.sh" "${VOLUME}/bdr-pi-firstrun.sh"
    cp "${ROOT_DIR}/docs/setup.sh" "${VOLUME}/bdr-pi-setup.sh"

    perror
    perror "Ejecting ${DISK}..."

    ${SAFE} diskutil eject "${DISK}" || \
        abort "failed to eject ${DISK}, but I think I'm done..."

    perror "Done!"

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
