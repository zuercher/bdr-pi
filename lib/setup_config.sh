#!/bin/bash

#{{begin_exclude}}#
if [[ -n "${_SETUP_CONFIG_SH_INCLUDED:-}" ]]; then
    return
fi
_SETUP_CONFIG_SH="${BASH_SOURCE[0]}"
_SETUP_CONFIG_LIB_DIR="$(cd "$(dirname "${_SETUP_CONFIG_SH}")" && pwd)"
_SETUP_CONFIG_SH_INCLUDED=1
source "${_SETUP_CONFIG_LIB_DIR}/io.sh"
#{{end_exclude}}#

_SETUP_CONFIG_KEYS=()
_SETUP_CONFIG_VALUES=()
_SETUP_CONFIG_LOADED="false"

_debug() {
    perror "$@"
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
