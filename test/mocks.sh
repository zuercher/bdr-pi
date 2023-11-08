#!/bin/bash

_MOCKS=()
_MOCK_CALLS=()

_join_by() {
    local IFS="$1"
    shift
    echo "$*"
}

_copy_function() {
    test -n "$(declare -f "$1")" || return
    eval "${_/$1/$2}"
}

_rename_function() {
    _copy_function "$@" || return
    unset -f "$1"
}

_success_mock() {
    local NAME="${1:-}"
    if [[ -z "${NAME}" ]]; then
        echo "invalid mock function call (missing name)"
        exit 1
    fi
    shift

    _MOCK_CALLS+=("${NAME};$(_join_by ';' "$@")")
    return 0
}

_error_mock() {
    local NAME="${1:-}"
    if [[ -z "${NAME}" ]]; then
        echo "invalid mock function call (missing name)"
        exit 1
    fi
    shift

    _MOCK_CALLS+=("${NAME};$(_join_by ';' "$@")")
    return 1
}

# mock_success $1=fn-name
mock_success() {
    local FN="${1:-}"
    if [[ -z "${FN}" ]]; then
        echo "mock_success requires function name"
        exit 1
    fi

    if ! _rename_function "${FN}" "${FN}__save__"; then
        echo "function ${FN} not found"
        exit 1
    fi

    _MOCKS+=("${FN}")

    eval "function ${FN}() { _success_mock '${FN}' \"\$@\"; }"
}

# mock_error $1=fn-name
mock_error() {
    local FN="${1:-}"
    if [[ -z "${FN}" ]]; then
        echo "mock_error requires function name"
        exit 1
    fi

    if ! _rename_function "${FN}" "${FN}__save__"; then
        echo "function ${FN} not found"
        exit 1
    fi

    _MOCKS+=("${FN}")

    eval "function ${FN}() { _error_mock '${FN}' \"\$@\"; }"
}

clear_mocks() {
    for FN in "${_MOCKS[@]}"; do
        if ! _rename_function "${FN}__save__" "${FN}"; then
            echo "failed to unmock ${FN}"
            exit 1
        fi
    done

    _MOCKS=()
    _MOCK_CALLS=()
}

clear_mock_calls() {
    _MOCK_CALLS=()
}

expect_mock_called() {
    local FN="${1:-}"
    if [[ -z "${FN}" ]]; then
        echo "expect_mock_called requires function name"
        exit 1
    fi

    local CALL
    local FOUND=false
    for CALL in "${_MOCK_CALLS[@]}"; do
        if [[ "${CALL}" =~ ${FN}\;.* ]]; then
            FOUND=true
            break
        fi
    done

    if ! "${FOUND}"; then
        echo "mock ${FN} was not called"
        exit 1
    fi
    return 0
}

expect_mock_not_called() {
    local FN="${1:-}"
    if [[ -z "${FN}" ]]; then
        echo "expect_mock_called requires function name"
        exit 1
    fi

    local CALL
    local FOUND=false
    for CALL in "${_MOCK_CALLS[@]}"; do
        if [[ "${CALL}" =~ ${FN}\;.* ]]; then
            FOUND=true
            break
        fi
    done

    if "${FOUND}"; then
        echo "mock ${FN} was called"
        exit 1
    fi
    return 0
}

expect_mock_called_with_args() {
    local FN="${1:-}"
    if [[ -z "${FN}" ]]; then
        echo "expect_mock_called requires function name"
        exit 1
    fi
    shift

    local EXPECTED_CALL
    EXPECTED_CALL="${FN};$(_join_by ';' "$@")"

    local CALL
    local FOUND=false
    for CALL in "${_MOCK_CALLS[@]}"; do
        if [[ "${CALL}" == "${EXPECTED_CALL}" ]]; then
            FOUND=true
            break
        fi
    done

    if ! "${FOUND}"; then
        echo "mock ${FN} was not called with $*"
        exit 1
    fi
}
