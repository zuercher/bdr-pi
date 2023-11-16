#!/bin/bash

init_test_tmpdir() {
    local NAME
    NAME="$(mktemp -d /tmp/bdr-pi-test.XXXXXX)"

    if [[ -z "${NAME}" ]]; then
        echo "failed to make temp dir" >/dev/stderr
        return 1
    fi

    echo "${NAME}"
}

_TEST_TMPDIR="$(init_test_tmpdir)" || exit 1
#trap '[[ -n "${_TEST_TMPDIR}" ]] && rm -rf "${_TEST_TMPDIR}"' EXIT

mk_test_tmpdir() {
    echo "${_TEST_TMPDIR}"
}

mk_test_tmpfile() {
    local DIR NAME

    DIR="$(mk_test_tmpdir)" || return 1
    NAME="$(mktemp "${DIR}/bdr-pi-test.XXXXXX")"

    if [[ -z "${NAME}" ]]; then
        echo "failed to make temp file" >/dev/stderr
        return 1
    fi

    echo "${NAME}"
}

capture_output_bg() {
    local FILE
    FILE="$(mk_test_tmpfile)" || exit 1

    "$@" &>"${FILE}" &
    local PID="$!"

    echo "${PID}:${FILE}"
}

kill_bg() {
    local HANDLE="$1"

    local PID="${HANDLE%%:*}"

    if [[ -z "${PID}" ]] || [[ "${PID}" -eq 0 ]]; then
        echo "handle ${HANDLE} has no pid"
        exit 1
    fi

    kill -s SIGINT "${PID}"
    wait "${PID}" 2>/dev/null
}

output_file() {
    local HANDLE="$1"

    local FILE="${HANDLE#*:}"

    if [[ -z "${FILE}" ]]; then
        echo "handle ${HANDLE} has no file"
        return 1
    fi

    echo "${FILE}"
}
