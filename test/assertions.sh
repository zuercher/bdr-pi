#!/bin/bash

assert_failed() {
    echo "$@"
    exit 1
}

assert_eq() {
    [[ "$#" -eq 2 ]] || assert_failed "assert_eq missing arguments (got $#, not 2)"

    [[ "${1}" == "${2}" ]] || assert_failed "assert eq: ${1} != ${2}"
}

assert_ne() {
    [[ "$#" -eq 2 ]] || assert_failed "assert_ne missing arguments (got $#, not 2)"

    [[ "${1}" != "${2}" ]] || assert_failed "assert ne: ${1} == ${2}"
}

assert_succeeds() {
    "$@" || assert_failed "command $*: failed with rc $?"
}

assert_fails() {
    "$@" && assert_failed "command $*: passed with rc $?"
    return 0
}

assert_exit_code() {
    local EC="$1"
    shift

    "$@"
    local GOT="$?"
    [[ "${GOT}" -eq 0 ]] && assert_failed "command $*: passed with rc $?"
    [[ "${GOT}" -ne "${EC}" ]] && assert_failed "command $*: failed with rc ${GOT}, but wanted ${EC}"

    return 0
}

assert_stderr_contains() {
    local EXPECTED="$1"
    shift

    local STDERR
    STDERR="$( "$@" 2>&1 >/dev/null || :)"

    if [[ "${STDERR}" =~ ${EXPECTED} ]]; then
        return 0
    fi

    assert_failed "command $*: expected stderr with ${EXPECTED}; got ${STDERR}"
}

assert_stdout_contains() {
    local EXPECTED="$1"
    shift

    local STDOUT
    STDOUT="$( "$@" 2>/dev/null)" || :

    if [[ "${STDOUT}" =~ ${EXPECTED} ]]; then
        return 0
    fi

    assert_failed "command $*: expected stdout with ${EXPECTED}; got ${STDOUT}"
}
