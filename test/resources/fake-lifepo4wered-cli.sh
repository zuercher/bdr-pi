#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_SCRIPT_DIR="$(cd "$(dirname "${_TEST_SH}")" && pwd)"

_VOLTAGE_FILE="${_SCRIPT_DIR}/.fake-voltage"

if [[ "$1" == "get" ]] && [[ "$2" == "vin" ]]; then
    if [[ -f "${_VOLTAGE_FILE}" ]]; then
        cat "${_VOLTAGE_FILE}"
        exit 0
    fi
    echo "4987"
    exit 0
fi

echo "fake_lifepo4wered-cli.sh bad args: $*" >/dev/stderr
exit 1
