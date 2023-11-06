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

# prompt_pw $1...=prompt
#   prompts the user with terminal echo disabled and returns their
#   response, which may be empty
prompt_pw() {
    local ANSWER

    read -ers -p "$*: " ANSWER
    echo "${ANSWER}"
}

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

tmpfile() {
    local name="${BDRPI_TMP:-/tmp}/${1:-tmp}"
    echo "${name}"
}
trap 'rm -rf "${BDRPI_TMP}"' EXIT

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

get_images() {
    local OSLIST="$(tmpfile oslist-json)"

    curl -s "${OSLIST_URL}" >"${OSLIST}" || abort "failed to download image list"

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

list_images() {
    local IMAGELIST="$(get_images "$@")"

    jq -r '.name + "\n\t" + .url + "\n"' "${IMAGELIST}"

    return 0
}

prep_image() {
    IMAGE="${1}"

    if [[ "${IMAGE}" = *.xz ]]; then
        local BASE="$(basename "${IMAGE}")"
        local RESULT="$(tmpfile "${BASE/%\.xz/}")"
        if [[ ! -f "${RESULT}" ]]; then
            xz --decompress --stdout --thread=2 "${IMAGE}" > "${RESULT}"
        fi
        echo "${RESULT}"
    else
        echo "${IMAGE}"
    fi
}

download_image() {
    local IMAGEURL="${1:-}"
    local HASH="${2:-}"

    if [[ -z "${IMAGEURL}" ]]; then
        abort "internal error: no image url"
    fi

    local FILE="$(basename "${IMAGEURL}")"
    local CACHE_FILE="${CACHE_DIR}/${FILE}"

    if [[ -f "${CACHE_FILE}" ]]; then
        echo "using cached file ${CACHE_FILE}" >/dev/stderr
    else
        echo "downloading ${IMAGEURL}" >/dev/stderr

        curl --progress-bar --output "${CACHE_FILE}" "${IMAGEURL}" || \
            abort "failed to download ${IMAGEURL}"
    fi

    if [[ -n "${HASH}" ]]; then
        echo "validating file..." >/dev/stderr

        local FILE="$(prep_image "${CACHE_FILE}")"
        local FILEHASH="$(shasum -a 256 "${FILE}" | awk '{print $1}')"

        [[ "${FILEHASH}" == "${HASH}" ]] || abort "hash mismatch got ${FILEHASH}, expected ${HASH}"

        echo "ok" >/dev/stderr
    fi

    echo "${CACHE_FILE}"
}

image() {
    local DISK="${1:-}"
    if [[ -z "${DISK}" ]]; then
        usage "ERROR: image: missing disk name argument"
    fi

    local SAFE=""
    if "${DRYRUN}"; then
        echo "Dry-run mode enabled."
        SAFE="echo"
    fi

    local IMAGELIST="$(get_images "$@")"

    echo "Select base image:"
    jq -r '.name' "${IMAGELIST}" | nl -s $'.\t'

    local DEFAULT="$(
        jq -r '.name' "${IMAGELIST}" | \
        nl -s: -w1 | \
        grep Legacy | grep 64-bit | grep Lite |\
        cut -d: -f1)"

    local PICK="$(prompt_default "${DEFAULT}" "Which image?")"

    local IMAGEURL="$(
        jq -r '.url' "${IMAGELIST}" | \
        nl -s: -w1 | \
        grep -E "^${PICK}:" |\
        cut -d: -f2-)"
    local IMAGEHASH="$(
        jq -r '.sha' "${IMAGELIST}" | \
        nl -s: -w1 | \
        grep -E "^${PICK}:" |\
        cut -d: -f2-)"

    IMAGE="$(download_image "${IMAGEURL}" "${IMAGEHASH}")"

    local PLIST="$(tmpfile disk-plist)"
    diskutil info -plist "${DISK}" >"${PLIST}" || abort "error getting disk info"

    local SIZE="$(plutil -extract "Size" raw "${PLIST}")"
    if [[ -z "${SIZE}" ]]; then
        abort "failed to determine disk size"
    fi
    if [[ "${SIZE}" -lt 32000000000 ]]; then
        abort "volume is less than 32 GiB... giving up"
    fi
    let SIZE_GB=(SIZE / 1000000000)

    echo "Volume size is approximately ${SIZE_GB} GiB (${SIZE})."

    local BLOCKSIZE="$(plutil -extract "DeviceBlockSize" raw "${PLIST}")"
    if [[ -z "${BLOCKSIZE}" ]] || [[ "${BLOCKSIZE}" -eq 0 ]]; then
        abort "cannot determine block size"
    fi
    echo "Block size is ${BLOCKSIZE}."

    # rewrite /dev/diskX to /dev/rdiskX
    RDISK="${DISK//\/dev\/disk//dev/rdisk}"

    # format the disk
    ${SAFE} sudo diskutil eraseDisk FAT32 "BDR_PI" MBRFormat "${DISK}" || \
        abort "format operation failed"

    # unmount the disk
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
    echo "Writing image to disk... this could take a while..."

    # Write the image. rpi-imager skips the first 4kb and then writes
    # it last. Not sure why.
    ${SAFE} sudo dd bs=1m if="$(prep_image "${IMAGE}")" of="${RDISK}" status=progress

    echo "...done"

    # remount the disk
    ${SAFE} diskutil mountDisk "${DISK}" || abort "failed to re-mount disk"

    return 0
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
