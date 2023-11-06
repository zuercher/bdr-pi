#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_TEST_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")" && pwd)"

cd "${_TEST_ROOT_DIR}" || { echo "failed to cd to ${_TEST_ROOT_DIR}"; exit 1; }

FAILED=false
for TEST in "$(find . -type f -a -name "test_*.sh" -print)"; do
    echo "test/${TEST#./}:"
    if "${TEST}"; then
        echo "pass"
    else
        echo "FAILED"
        FAILED=true
    fi
    echo
done

if "${FAILED}"; then
    echo "One or more test suites failed."
    exit 1
fi

echo "All tests passed."
exit 0
