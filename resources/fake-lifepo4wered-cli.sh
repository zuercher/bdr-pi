#!/bin/bash

_VOLTAGE_FILE="/tmp/.bdr-pi-fake-voltage"

if [[ "$1" == "get" ]] && [[ "$2" == "vin" ]]; then
    if [[ -f "${_VOLTAGE_FILE}" ]]; then
        cat "${_VOLTAGE_FILE}"
        exit 0
    fi
    echo "4987"
    exit 0
fi

if [[ "$1" == "set" ]] && [[ "$2" == "vin" ]] && [[ -n "$3" ]]; then
    echo "$3" >"${_VOLTAGE_FILE}"
    exit 0
fi

echo "fake_lifepo4wered-cli.sh bad args: $*" >/dev/stderr
exit 1
