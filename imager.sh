#!/bin/bash

#/# Usage: imager.sh <command> <options>
#/#
#/# Commands:
#/#     list-disks [--all]
#/#         List available disks for imaging. Defaults to physical,
#/#         external disks. Use the --all flag to see all disks.
#/#

set -u

DRYRUN="false"

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

# print usage and quit
usage() {
    if [[ -n "$1" ]]; then
        perror "$@"
        perror ""
    fi
    grep "^#/#" "$0" | cut -c"5-" >&2
    exit 1
}

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

    local PLIST="${TMPDIR:-/tmp}/.disk-plist.$$"
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

    rm -f "${PLIST}"

    if [[ "${TOTAL}" -eq 0 ]]; then
        echo "No disks found."
    fi

    return 0
}

image() {
    local DISK="${1:-}"
    if [[ -z "${DISK}" ]]; then
        usage "ERROR: image: missing disk name (see list-disks)"
    fi

    SAFE=""
    if "${DRYRUN}"; then
        echo "Dry-run mode enabled."
        SAFE="echo"
    fi

    local PLIST="${TMPDIR:-/tmp}/.disk-plist.$$"
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

    rm -f "${PLIST}"

    # TODO: download image (need a list images thingy?)
    # TODO: check hash?

    # rewrite /dev/diskX to /dev/rdiskX
    RDISK="${DISK//\/dev\/disk//dev/rdisk}"

    # format the disk
    ${SAFE} sudo diskutil eraseDisk FAT32 SDCARD MBRFormat "${DISK}" || \
        abort "format operation failed"

    # unmount the disk
    ${SAFE} diskutil unmountDisk "${DISK}" || abort "failed to unmount disk"

    # zero first MB
    let NBLKS=(1024*1024 / BLOCKSIZE)
    ${SAFE} sudo dd bs="${BLOCKSIZE}" count="${NBLKS}" \
            if=/dev/zero \
            of="${RDISK}" || abort "failed to zero first MB"

    # zero last MB
    let SIZE_BLKS=(SIZE / 512)
    let SBLKS=(SIZE_BLKS - NBLKS)
    ${SAFE} sudo dd bs="${BLOCKSIZE}" oseek="${SBLKS}" count="${NBLKS}" \
            if=/dev/zero \
            of="${RDISK}" || abort "failed to zero last MB"


    # TODO: raspberry pi imager skips first 4kb (partition table), why?
    # TODO: write image to disk (dd?)
    # TODO: flush?

    # TODO: eject? (diskutil?)

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

for TOOL in diskutil jot plutil; do
    if ! installed "${TOOL}"; then
        abort "could not find ${TOOL}, is this macOS?"
    fi
done

while [[ -n "${1:-}" ]]; do
    case "$1" in
        -n|-dry-run|--dry-run)
            DRYRUN=true
            shift
            ;;

        list|list-disks)
            shift
            list_disks "$@"
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
