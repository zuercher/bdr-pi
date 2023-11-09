#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_TEST_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")" && pwd)"

cd "${_TEST_ROOT_DIR}" || { echo "failed to cd to ${_TEST_ROOT_DIR}"; exit 1; }

FAILED=false
while IFS= read -d $'\0' TEST_FILE; do
    echo "test/${TEST_FILE#./}:"
    if ( "${TEST_FILE}" ); then
        echo "pass"
    else
        echo "FAILED"
        FAILED=true
    fi
    echo
done < <(find -s . -type f -a -name "test_*.sh" -print0)

if "${FAILED}"; then
    echo "One or more test suites failed."
    exit 1
fi

echo "All tests passed."
exit 0
