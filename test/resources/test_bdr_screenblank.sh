#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_TEST_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/.. && pwd)"
_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/../.. && pwd)"

source "${_TEST_ROOT_DIR}/assertions.sh"
source "${_TEST_ROOT_DIR}/io.sh"

_FAKE_VOLTAGE_FILE="${_TEST_ROOT_DIR}/resources/.fake-voltage"

await() {
    local MAX_WAIT="$1"
    local FILE="$2"
    local CONTENTS="$3"

    local N=0
    while true; do
        N=$((N + 1))

        if [[ "${N}" -gt "${MAX_WAIT}" ]]; then
            echo "exceeded max attempts waiting on ${FILE} to contain ${CONTENTS}"
            exit 1
        fi

        if [[ -e "${FILE}" ]]; then
            local DATA
            DATA="$(cat "${FILE}")"
            if  [[ "${DATA}" == "${CONTENTS}" ]]; then
                break
            fi
        fi

        sleep 1
    done

    return 0
}

test_bdr_screenblank() {
    local BLANK_FILE
    BLANK_FILE="$(mk_test_tmpfile)" || exit 1

    touch "${BLANK_FILE}"

    echo "5000" >"${_FAKE_VOLTAGE_FILE}"

    local HANDLE
    capture_output_bg \
        "${_ROOT_DIR}/resources/bdr_screenblank.sh" \
        --blank-interval=1 --wake-interval=1 \
        --lifepo4wered-binary="${_TEST_ROOT_DIR}/resources/fake-lifepo4wered-cli.sh" \
        --path="${BLANK_FILE}" |
        while read HANDLE; do
            await 10 "${BLANK_FILE}" "0" || assert_failed "blank file was not written with 0"

            echo "500" >"${_FAKE_VOLTAGE_FILE}"

            await 10 "${BLANK_FILE}" "1" || assert_failed "blank file was not written with 1"

            echo "4999" >"${_FAKE_VOLTAGE_FILE}"

            await 10 "${BLANK_FILE}" "0" || assert_failed "blank file was not written with 0 again"

            kill_bg "${HANDLE}"

            local OUTPUT
            OUTPUT="$(output_file "${HANDLE}")"
            assert_succeeds grep -q "VIN: 5000 mV" "${OUTPUT}"
            assert_succeeds grep -q "VIN: 500 mV" "${OUTPUT}"
            assert_succeeds grep -q "VIN: 4999 mV" "${OUTPUT}"
        done
}

test_bdr_screenblank_args() {
    local CMD="${_ROOT_DIR}/resources/bdr_screenblank.sh"

    assert_fails "${CMD}" --blank-threshold=9999 2>/dev/null
    assert_stderr_contains "blank-threshold must be between" "${CMD}" --blank-threshold=9999

    assert_fails "${CMD}" --wake-threshold=9999 2>/dev/null
    assert_stderr_contains "wake-threshold must be between" "${CMD}" --wake-threshold=9999

    assert_fails "${CMD}" --wake-threshold=1000 --blank-threshold=3000 2>/dev/null
    assert_stderr_contains "blank-threshold must be between" "${CMD}" --wake-threshold=1000 \
                           --blank-threshold=3000

    assert_fails "${CMD}" --blank-interval=9999 2>/dev/null
    assert_stderr_contains "blank-interval must be between" "${CMD}" --blank-interval=9999

    assert_fails "${CMD}" --wake-interval=9999 2>/dev/null
    assert_stderr_contains "wake-interval must be between" "${CMD}" --wake-interval=9999

    assert_fails "${CMD}" --path "" 2>/dev/null
    assert_fails "${CMD}" --path "/tmp/nopenopenope.$$" 2>/dev/null

}

source "${_TEST_ROOT_DIR}/test-harness.sh"
