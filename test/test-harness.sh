#!/bin/bash

runsuite() {
    declare -a SUITE

    local BEFORE_EACH AFTER_EACH BEFORE_ALL AFTER_ALL

    for F in $(declare -F | awk '{print $3}'); do
        case "${F}" in
            test_*)
                SUITE+=("${F}")
                ;;
            before_each)
                BEFORE_EACH="${F}"
                ;;
            after_each)
                AFTER_EACH="${F}"
                ;;
            before_all)
                BEFORE_ALL="${F}"
                ;;
            after_all)
                AFTER_ALL="${F}"
                ;;
        esac
    done

    if [[ "${#SUITE[@]}" -eq 0 ]]; then
        echo "  No tests found."
        return 1
    fi

    local TEST START END DURATION
    local TEST_OUTPUT="${TMPDIR:-/tmp/}/.bdr-pi-tests.$$"
    local FAILED=false

    if [ -n "${BEFORE_ALL}" ]; then
        "${BEFORE_ALL}"
    fi

    for TEST in "${SUITE[@]}"; do
        rm -f "${TEST_OUTPUT}"

        if [ -n "${BEFORE_EACH}" ]; then
            "${BEFORE_EACH}"
        fi

        local FAILED_TEST=false
        echo -n "  $TEST: "
        START="$(date '+%s')"
        if ( "${TEST}" > "${TEST_OUTPUT}" ); then
            echo -n "ok "
        else
            echo -n "FAILED "
            FAILED_TEST=true
            FAILED=true
        fi
        END="$(date '+%s')"

        let DURATION=END-START
        echo "(${DURATION}s)"

        if "${FAILED_TEST}"; then
            cat "${TEST_OUTPUT}" | sed -e "s/^/      /"
        fi

        if [ -n "${AFTER_EACH}" ]; then
            "${AFTER_EACH}"
        fi
    done

    if [ -n "${AFTER_ALL}" ]; then
        "${AFTER_ALL}"
    fi

    rm -f "${TEST_OUTPUT}"

    if "${FAILED}"; then
        return 1
    else
        return 0
    fi
}

runsuite || exit 1