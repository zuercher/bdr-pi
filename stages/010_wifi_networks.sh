#!/bin/bash

run_stage() {
    local IFACE
    IFACE="$(wireless_first_interface)"
    [[ -z "${IFACE}" ]] && abort "no wireless interface found"

    wireless_wpa_check "${IFACE}" || exit 1

    # It's possible that our initial setup was done with a wired
    # network connection, so run the wireless device setup. It should
    # be a no-op if already done.
    wireless_device_setup
    local RC=$?
    if [[ "${RC}" == 10 ]]; then
        report "wireless device regulatory setup requires a reboot"
        reboot_required
        return 0
    elif [[ "${RC}" != 0 ]]; then
        abort "wireless device regulatory config failed, good luck!"
    fi

    local DEFAULT_PRIO_SSIDS
    local HIGH_PRIO_SSIDS
    declare -a DEFAULT_PRIO_SSIDS
    declare -a HIGH_PRIO_SSIDS
    local NUM_IDS=0
    local ID
    for ID in $(wireless_list_network_ids); do
        DESC=$(wireless_describe_network "${ID}")
        local PRIO
        PRIO="$(echo "${DESC}" | cut -d: -f1)"
        local SSID
        SSID="$(echo "${DESC}" | cut -d: -f2-)"

        if [[ "${PRIO}" == 0 ]]; then
            DEFAULT_PRIO_SSIDS+=("${SSID}")
        else
            HIGH_PRIO_SSIDS+=("${SSID}")
        fi
        NUM_IDS=$((NUM_IDS + 1))
    done

    if [[ "${NUM_IDS}" -gt 0 ]]; then
        report "found existing wireless networks:"
        report "  default priority:"
        for ID in "${DEFAULT_PRIO_SSIDS[@]}"; do
            report "    ${ID}"
        done
        report "  high priority:"
        for ID in "${HIGH_PRIO_SSIDS[@]}"; do
            report "    ${ID}"
        done
    fi

    while true; do
        local RESP
        RESP="$(prompt "add a high priority SSID? [y/N]") | tr '[:lower]' '[:upper:]'"
        if [[ "${RESP}" != "Y" ]] && [[ "${RESP}" != "YES" ]]; then
            break
        fi

        wireless_add_network 10
    done
}
