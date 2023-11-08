#!/bin/bash

_MOCK_FUNCS=()
_MOCK_OTHERS=()
_MOCK_DIR="${TMPDIR:-/tmp/}bdrpi-test-mocks.$$"
_MOCK_CALLS="${_MOCK_DIR}/mock-calls"

mkdir -p "${_MOCK_DIR}"
trap 'rm -rf "${_MOCK_DIR}"' EXIT

_join_by() {
    local IFS="$1"
    shift
    echo "$*"
}

_is_function() {
    test -n "$(declare -f "$1")"
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

    echo "${NAME};$(_join_by ';' "$@")" >>"${_MOCK_CALLS}"
    return 0
}

_error_mock() {
    local NAME="${1:-}"
    if [[ -z "${NAME}" ]]; then
        echo "invalid mock function call (missing name)"
        exit 1
    fi
    shift

    echo "${NAME};$(_join_by ';' "$@")" >>"${_MOCK_CALLS}"
    return 1
}

# mock_success $1=fn-name
mock_success() {
    local FN="${1:-}"
    if [[ -z "${FN}" ]]; then
        echo "mock_success requires function name"
        exit 1
    fi

    if _is_function "${FN}"; then
        if ! _rename_function "${FN}" "${FN}__save__"; then
            echo "function ${FN} could be renamed"
            exit 1
        fi
        _MOCK_FUNCS+=("${FN}")
    else
        _MOCK_OTHERS+=("${FN}")
    fi

    eval "function ${FN}() { _success_mock '${FN}' \"\$@\"; }"
}

# mock_success_and_set $1=fn-name $2=variable $3=value
# Mocks the function and sets the variable to value when
# the mock is invoked.
mock_success_and_set() {
    local FN="${1:-}"
    if [[ -z "${FN}" ]]; then
        echo "mock_success_and_set requires function name"
        exit 1
    fi

    local VAR="${2:-}"
    if [[ -z "${VAR}" ]]; then
        echo "mock_success_and_set requires variable name"
        exit 1
    fi

    local VAL="${3:-}"
    if [[ -z "${VAL}" ]]; then
        echo "mock_success_and_set requires variable value"
        exit 1
    fi

    if _is_function "${FN}"; then
        if ! _rename_function "${FN}" "${FN}__save__"; then
            echo "function ${FN} could be renamed"
            exit 1
        fi
        _MOCK_FUNCS+=("${FN}")
    else
        _MOCK_OTHERS+=("${FN}")
    fi

    eval "function ${FN}() { ${VAR}=\"${VAL}\"; _success_mock '${FN}' \"\$@\"; }"
}

# mock_success_and_return $1=fn-name $...=output
# Mocks the function and echos the remaining arguments when the mock
# is invoked.
mock_success_and_return() {
    local FN="${1:-}"
    if [[ -z "${FN}" ]]; then
        echo "mock_success_and_set requires function name"
        exit 1
    fi
    shift

    local OUTPUT="$*"

    if _is_function "${FN}"; then
        if ! _rename_function "${FN}" "${FN}__save__"; then
            echo "function ${FN} could be renamed"
            exit 1
        fi
        _MOCK_FUNCS+=("${FN}")
    else
        _MOCK_OTHERS+=("${FN}")
    fi

    eval "function ${FN}() { echo \"${OUTPUT}\"; _success_mock '${FN}' \"\$@\"; }"
}

# mock_error $1=fn-name
mock_error() {
    local FN="${1:-}"
    if [[ -z "${FN}" ]]; then
        echo "mock_error requires function name"
        exit 1
    fi

    if _is_function "${FN}"; then
        if ! _rename_function "${FN}" "${FN}__save__"; then
            echo "function ${FN} could be renamed"
            exit 1
        fi
        _MOCK_FUNCS+=("${FN}")
    else
        _MOCK_OTHERS+=("${FN}")
    fi

    eval "function ${FN}() { _error_mock '${FN}' \"\$@\"; }"
}

clear_mock_calls() {
    rm -f "${_MOCK_CALLS}"
}

clear_mocks() {
    for FN in "${_MOCK_FUNCS[@]}"; do
        if ! _rename_function "${FN}__save__" "${FN}"; then
            echo "failed to unmock function ${FN}"
            exit 1
        fi
    done
    for FN in "${_MOCK_OTHERS[@]}"; do
        if ! unset -f "${FN}"; then
            echo "failed to unmock function ${FN}"
            exit 1
        fi
    done

    _MOCK_FUNCS=()
    _MOCK_OTHERS=()
    clear_mock_calls
}

expect_mock_called() {
    local FN="${1:-}"
    if [[ -z "${FN}" ]]; then
        echo "expect_mock_called requires function name"
        exit 1
    fi

    local CALL

    if ! grep -q -E "^${FN}\;.*" "${_MOCK_CALLS}"; then
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

    if grep -q -E "^${FN}\;.*" "${_MOCK_CALLS}"; then
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

    if ! grep -q -F "${EXPECTED_CALL}" "${_MOCK_CALLS}"; then
        echo "mock ${FN} was not called with $*"
        echo "found these calls:"
        grep -E "^${FN};.*" "${_MOCK_CALLS}" || echo "(none)"
        exit 1
    fi
}
