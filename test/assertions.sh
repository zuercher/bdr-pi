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
