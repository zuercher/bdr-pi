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

    while IFS= read -r -d $'\0' VOLUME; do
        diskutil list -plist ${TYPES[@]:-} "${VOLUME}" >"${PLIST}"

        local NUM_DISKS="$(plutil -extract WholeDisks raw "${PLIST}")"
        if [[ "${NUM_DISKS}" -gt 0 ]]; then
            for INDEX in $(jot "${NUM_DISKS}" 0); do
                local DISK="$(plutil -extract "WholeDisks.${INDEX}" raw "${PLIST}")"
                if [[ -n "${DISK:-}" ]]; then
                    echo "/dev/${DISK}  ${VOLUME}"
                    let TOTAL=TOTAL+1
                fi
            done
        fi
    done < <(find -s /Volumes -depth 1 -print0)

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

    SAFE=""
    if "${DRYRUN}"; then
        echo "Dry-run mode enabled."
        SAFE="echo"
    fi



    ${SAFE} sudo diskutil eraseDisk FAT32 SDCARD MBRFormat "${DISK}" || \
        abort "format operation failed"

    # TODO: device should be /dev/rdisk?

    # TODO: write zero to first MB (dd)
    # TODO: write zero to last MB

    # TODO: download image (need a list images thingy?)
    # TODO: check hash?

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
