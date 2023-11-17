#!/bin/bash

# perror prints its arguments to stderr.
perror() {
    printf "%s\n" "$*" 1>&2
    return 0
}

# abort prints its arguments and quits
abort() {
    perror "$@"
    exit 1
}

usage() {
    if [[ -n "$1" ]]; then
        perror "ERROR: $1"
        echo
    fi
    echo "Usage:"
    echo "    $0 [options]"
    echo
    echo "Options:"
    echo "    --blank-threshold=MV"
    echo "        Sets the minimum battery voltage (in millivolts) before"
    echo "        the backlight is powered off. Default ${DEFAULT_BLANK_MV} mV."
    echo "    --wake-threshold=MV"
    echo "        Sets the maximum battery voltage (in millivolts) before"
    echo "        the backlight is powered on . Default ${DEFAULT_WAKE_MV} mV."
    echo "    --battery-blank-interval=S"
    echo "        Sets the interval (in seconds) between battery voltage"
    echo "        checks when the backlight is on. Controls how quickly the"
    echo "        screen is blanked. Default ${DEFAULT_BLANK_INTVL} s."
    echo "    --battery-wake-interval=S"
    echo "        Sets the interval (in seconds) between battery voltage"
    echo "        checks when the backlight is off. Controls how quickly the"
    echo "        screen is unblanked. Default ${DEFAULT_WAKE_INTVL} s."
    echo "    --daemon"
    echo "        Wait a bit before attempting to find the default device."
    echo "        (In lieu of figuring out proper inter-unit dependencies.)"
    echo "    --path=PATH"
    echo "        Set the path used to power the backlight on and off."
    echo "        Defaults to the first entry in /sys/class/backlight,"
    echo "        which is ${DEFAULT_DEVICE_PATH:-not available}."
    echo "    --lifepo4wered-binary=PATH"
    echo "        Set the binary used to query the current input voltage."
    echo "        Defaults to ${DEFAULT_BINARY}."
    exit 1
}

cutarg() {
    echo "$1" | cut -d= -f2-
}


# validate arg: $1=arg name, $2=value, $3=min-value, $4=max-value
validate() {
    local ARG="$1"
    local VALUE="$2"
    local MINVAL="$3"
    local MAXVAL="$4"

    [[ -z "${VALUE}" ]] && abort "ERROR: ${ARG} must have a value"

    if [[ "${VALUE}" -lt "${MINVAL}" ]] || [[ "${VALUE}" -gt "${MAXVAL}" ]]; then
        abort "ERROR: ${ARG} must be between ${MINVAL} and ${MAXVAL}, got ${VALUE}"
    fi

    return 0
}

default_path() {
    local DEVICE
    DEVICE="$(ls -1 /sys/class/backlight 2>/dev/null | head -n 1)"

    if [[ -z "${DEVICE}" ]]; then
        echo ""
        return 0
    fi

    echo "/sys/class/backlight/${DEVICE}/bl_power"
}

DEFAULT_BLANK_MV=3750
DEFAULT_WAKE_MV=4000
DEFAULT_BLANK_INTVL=5
DEFAULT_WAKE_INTVL=10
DEFAULT_DEVICE_PATH="$(default_path)"
DEFAULT_BINARY="lifepo4wered-cli"

BLANK_MV="${DEFAULT_BLANK_MV}"
WAKE_MV="${DEFAULT_WAKE_MV}"
BLANK_INTVL="${DEFAULT_BLANK_INTVL}"
WAKE_INTVL="${DEFAULT_WAKE_INTVL}"
DEVICE_PATH="${DEFAULT_DEVICE_PATH}"
BINARY="${DEFAULT_BINARY}"
DAEMON=false

while [[ -n "$1" ]]; do
    case "$1" in
        --blank-threshold|-blank-threshold)
            BLANK_MV="$2"
            shift 2
            ;;
        --blank-threshold=*|-blank-threshold=*)
            BLANK_MV="$(cutarg "$1")"
            shift
            ;;

        --wake-threshold|-wake-threshold)
            WAKE_MV="$2"
            shift 2
            ;;
        --wake-threshold=*|-wake-threshold=*)
            WAKE_MV="$(cutarg "$1")"
            shift
            ;;

        --blank-interval|-blank-interval)
            BLANK_INTVL="$2"
            shift 2
            ;;
        --blank-interval=*|-blank-interval=*)
            BLANK_INTVL="$(cutarg "$1")"
            shift
            ;;

        --wake-interval|-wake-interval)
            WAKE_INTVL="$2"
            shift 2
            ;;
        --wake-interval=*|-wake-interval=*)
            WAKE_INTVL="$(cutarg "$1")"
            shift
            ;;

        --daemon)
            DAEMON=true
            shift
            ;;

        --path|-path)
            DEVICE_PATH="$2"
            shift 2
            ;;
        --path=*|-path=*)
            DEVICE_PATH="$(cutarg "$1")"
            shift
            ;;

        --lifepo4wered-binary|-lifepo4wered-binary)
            BINARY="$2"
            shift 2
            ;;
        --lifepo4wered-binary=*|-lifepo4wered-binary=*)
            BINARY="$(cutarg "$1")"
            shift
            ;;

        --help|-help|-h)
            usage
            ;;
        *)
            usage "unknown argument $1"
            ;;
    esac
done

validate "blank-threshold" "${BLANK_MV}" 0 "${WAKE_MV:-5000}"
validate "wake-threshold" "${WAKE_MV}" "${BLANK_MV:-0}" 5000
validate "blank-interval" "${BLANK_INTVL}" 0 3600
validate "wake-interval" "${WAKE_INTVL}" 0 3600

if "${DAEMON}" && [[ -z "${DEVICE_PATH}" ]] && [[ -z "${DEFAULT_DEVICE_PATH}" ]]; then
    # In theory, we should be able to get systemd to start this script after
    # whatever magic configures /sys/class/backlight, but I can't figure it
    # out, so in the absence of path, wait a bit and see if a default appears.
    ATTEMPTS=0
    MAX_ATTEMPTS=$((300 / BLANK_INTVL))
    if [[ "${MAX_ATTEMPTS}" -lt 10 ]]; then
        MAX_ATTEMPTS=10
    fi

    while [[ -z "${DEFAULT_DEVICE_PATH}" ]]; do
        if [[ "${ATTEMPTS}" -ge "${MAX_ATTEMPTS}" ]]; then
            abort "ERROR: path must be set because a suitable default was not found (tried ${ATTEMPTS} times)"
        fi
        perror "waiting for default device to become available"
        sleep "${BLANK_INTVL}"
        DEFAULT_DEVICE_PATH="$(default_path)"

        ATTEMPTS=$((ATTEMPTS+1))
    done

    perror "found default device path ${DEFAULT_DEVICE_PATH}"
    DEVICE_PATH="${DEFAULT_DEVICE_PATH}"
elif [[ -z "${DEVICE_PATH}" ]]; then
    if [[ -z "${DEFAULT_DEVICE_PATH}" ]]; then
        abort "ERROR: path must be set because a suitable default was not found"
    fi
    abort "ERROR: path must be set to a non-empty value"
fi

[[ -e "${DEVICE_PATH}" ]] || abort "ERROR: path ${DEVICE_PATH} does not exist"

[[ -n "${BINARY}" ]] || abort "ERROR: binary must be set"

blank() {
    perror "blanking"
    echo -n "1" >"${DEVICE_PATH}"
}

wake() {
    perror "waking"
    echo -n "0" >"${DEVICE_PATH}"
}

get_vin() {
    "${BINARY}" get vin
}

trap 'wake' EXIT

STATE="AWAKE"
wake

while true; do
    CURR_VIN="$(get_vin)"
    perror "VIN: ${CURR_VIN} mV"

    if [[ "${STATE}" == "AWAKE" ]]; then
        # Ignore bad vin data and leave the display on.
        if [[ -n "${CURR_VIN}" ]] && [[ "${CURR_VIN}" -lt "${BLANK_MV}" ]]; then
            blank
            STATE="BLANK"
        fi
    elif [[ "${STATE}" == "BLANK" ]]; then
        # Wake the display in the event of bad vin data.
        if [[ -z "${CURR_VIN}" ]] || [[ "${CURR_VIN}" -gt "${WAKE_MV}" ]]; then
            wake
            STATE="AWAKE"
        fi
    else
        perror "ERROR: invalid state '${STATE}'"
        STATE="AWAKE"
        wake
    fi

    if [[ "${STATE}" == "BLANK" ]]; then
        sleep "${WAKE_INTVL}"
    else
        sleep "${BLANK_INTVL}"
    fi
done
