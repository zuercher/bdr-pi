#!/bin/bash

COUNTRY="${WIFI_DEFAULT_COUNTRY:-US}"

list_wireless_interfaces() {
    # Members of /sys/class/net are links, so find is troublesome.
    for dir in /sys/class/net/*/wireless; do
        if [ -d "$dir" ]; then
            basename "$(dirname "$dir")"
        fi
    done
}

wireless_reg_country() {
    iw reg get | sed -n -e "s/country \([A-Z]\+\):.*/\1/p"
}

run_stage() {
    report "setting wireless country to ${COUNTRY}"

    IFACE="$(list_wireless_interfaces | head -n 1)"
    [[ -n "${IFACE}" ]] || abort "no wireless interface found"

    if ! wpa_cli -i "${IFACE}" status > /dev/null; then
        abort "unable to get status from ${IFACE} -- wpa_supplicant problem?"
    fi

    local current_country="$(wpa_cli -i "${IFACE}" get country)"
    if [[ "${current_country}" != "${COUNTRY}" ]]; then
        wpa_cli -i "${IFACE}" set country "${COUNTRY}"
        wpa_cli -i "${IFACE}" save_config > /dev/null 2>&1
    else
        report "wpi_cli country is already ${COUNTRY}, skipping"
    fi

    local current_reg_country="$(wireless_reg_country)"
    if [[ "${current_reg_country}" != "${COUNTRY}" ]]; then
        if iw reg set "${COUNTRY}" 2> /dev/null; then
            requires_reboot
        fi
    else
        report "wireless device regulatory country is already ${COUNTRY}, skipping"
    fi

    if installed rfkill; then
        rfkill unblock wifi
        for filename in /var/lib/systemd/rfkill/*:wlan; do
            echo 0 > "${filename}"
        done
    fi
}
