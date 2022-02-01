#!/bin/bash

function usage() {
    echo "usage: $0 [options] [--] [simulator-options]"
    echo
    echo "Options:"
    echo "  --reinstall  re-install the kernel module"
    exit 1;
}

REINSTALL=false
SIM_ARGS=()

while [[ -n "$1" ]]; do
    case "$1" in
        -reinstall|--reinstall|-re-install|--re-install)
            REINSTALL=true
            shift
            ;;
        --)
            shift
            SIM_ARGS+=( "$@" )
            shift $#
            ;;
        *)
            usage
            ;;
    esac
done

DIR="$(cd "$(dirname "$0")" && pwd)"

KERNEL_MOD="${DIR}/bridge/fake_racecap_tty.ko"
KERNEL_MOD_NAME="$(basename -s .ko "${KERNEL_MOD}")"

if [[ ! -f "${KERNEL_MOD}" ]]; then
    echo "expected ${KERNEL_MOD}, but was not found"
    echo "  try: cd ${DIR}/bridge && make"
    exit 1
fi

KERNEL_MOD_INSTALLED=false
if lsmod | grep -q "${KERNEL_MOD_NAME}" >/dev/null; then
    echo "found ${KERNEL_MOD_NAME}"
    KERNEL_MOD_INSTALLED=true
fi

if "${KERNEL_MOD_INSTALLED}" && "${REINSTALL}"; then
    echo "removing ${KERNEL_MOD_NAME}"
    if ! sudo rmmod "${KERNEL_MOD_NAME}"; then
        echo "removal of ${KERNEL_MOD_NAME} failed"
        exit 1
    fi
    KERNEL_MOD_INSTALLED=false
fi

if ! "${KERNEL_MOD_INSTALLED}"; then
    echo "installing ${KERNEL_MOD_NAME}"
    if ! sudo insmod "${KERNEL_MOD}"; then
        echo "installation of ${KERNEL_MODE_NAME} failed"
        exit 1
    fi
fi

if [[ "${VIRTUAL_ENV}" != "${DIR}/pyenv" ]]; then
    source "${DIR}/pyenv/bin/activate"
fi

exec "${DIR}/simulator.py" "${SIM_ARGS[@]}"
