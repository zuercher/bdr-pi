#!/bin/bash

#{{begin_exclude}}#
if [[ -n "${_NETWORK_SH_INCLUDED:-}" ]]; then
    return
fi
_NETWORK_SH_INCLUDED=1
_NETWORK_SH="${BASH_SOURCE[0]}"
_NETWORK_LIB_DIR="$(cd "$(dirname "${_NETWORK_SH}")" && pwd)"
source "${_NETWORK_LIB_DIR}/io.sh"
source "${_NETWORK_LIB_DIR}/fs.sh"
#{{end_exclude}}#

# network_can_reach <url> tests if the current network can reach the
# given URL.
network_can_reach() {
    local URL="$1"

    curl -fsL --output /dev/null "${URL}"
}

# wireless_list_interfaces returns the name of the wireless network
# interfaces available on the system.
wireless_list_interfaces() {
    # Members of /sys/class/net are links, so find is troublesome.
    for dir in /sys/class/net/*/wireless; do
        if [ -d "$dir" ]; then
            basename "$(dirname "$dir")"
        fi
    done
}

# wireless_first_interface returns the first entry from
# wireless_list_interfaces.
wireless_first_interface() {
    wireless_list_interfaces | head -n 1
}

# wireless_reg_get_country reports the regulatory country that the
# wireless chipset reports.
wireless_reg_get_country() {
    iw reg get | sed -n -e "s/country \([A-Z]\+\):.*/\1/p"
}

# wireless_reg_set_country <country-code> sets the regulatory country
# on the wireless chipset.
wireless_reg_set_country() {
    local COUNTRY="$1"
    iw reg set "${COUNTRY}" 2> /dev/null
}

# wireless_wpa_check tests if wpa_supplicant is installed and
# operating. An error is printed if it fails.
wireless_wpa_check() {
    local IFACE="$1"

    if ! wpa_cli -i "${IFACE}" status > /dev/null; then
        perror "unable to get status from ${IFACE} -- wpa_supplicant problem?"
        return 1
    fi
    return 0
}

# wireless_wpa_get_country <iface> retrieves the current regulatory
# country as known to wpa_supplicant.
wireless_wpa_get_country() {
    local IFACE="$1"
    wpa_cli -i "${IFACE}" get country
}

# wireless_wpa_set_country <iface> <country-code> sets the
# current regulatory country as known to wpa_supplicant.
wireless_wpa_set_country() {
    local IFACE="$1"
    local COUNTRY="$2"
    wpa_cli -i "${IFACE}" set country "${COUNTRY}" && \
        wpa_cli -i "${IFACE}" save_config > /dev/null 2>&1
}

# wireless_disable_rfkill disables rfkill on all wireless LAN devices.
wireless_disable_rfkill() {
    if installed rfkill; then
        rfkill unblock wifi
        for filename in /var/lib/systemd/rfkill/*:wlan; do
            echo 0 > "${filename}"
        done
    fi
}

# wireless_device_setup attempts to setup wireless networking. Error
# code 10 indicates a reboot is required. Defaults to US regulatory
# networking unless BDRPI_WIFI_COUNTRY is set.
wireless_device_setup() {
    local COUNTRY="${BDRPI_WIFI_COUNTRY:-US}"

    local IFACE
    IFACE="$(wireless_first_interface)"
    [[ -z "${IFACE}" ]] && abort "no wireless interface found"

    wireless_wpa_check "${IFACE}" || exit 1

    if [[ "$(wireless_wpa_get_country "${IFACE}" )" != "${COUNTRY}" ]]; then
        report "setting wireless country to ${COUNTRY}"
        wireless_wpa_set_country "${IFACE}" "${COUNTRY}"
    else
        report "wpa_cli country is already ${COUNTRY}, skipping"
    fi

    RC=0
    if [[ "$(wireless_reg_get_country)" != "${COUNTRY}" ]]; then
        report "setting wireless device regulatory country to ${COUNTRY}"
        wireless_reg_set_country "${COUNTRY}"
        # we need to reboot now, apparently
        RC=10
    else
        report "wireless device regulatory country is already ${COUNTRY}, skipping"
    fi

    wireless_disable_rfkill

    return ${RC}
}

# wireless_add_network $1=priority adds a single SSID to the network
# configuration with the given priority (0 is lowest).
wireless_add_network() {
    local PRIORITY="$1"

    local SSID=""
    while [[ -z "${SSID}" ]]; do
        SSID=$(prompt "Wireless SSID")
    done
    local PSK=""
    while [[ -z "${PSK}" ]]; do
        PSK=$(prompt_pw "Wireless passphrase for ${SSID}")
    done

    wpa_cli -i "${IFACE}" list_networks \
        | tail -n +2 | cut -f -2 \
        | while read -r ID NAME; do
        if [[ "${NAME}" == "${SSID}" ]]; then
            report "removing existing network ${NAME}..."
            wpa_cli -i "${IFACE}" remove_network "${ID}" >/dev/null 2>&1
        fi
    done

    report "creating network ${SSID}"
    local ID
    ID="$(wpa_cli -i "${IFACE}" add_network)"

    wpa_cli -i "${IFACE}" set_network "${ID}" ssid "\"${SSID}\"" 2>&1 | grep -q "OK"
    RC=$?

    wpa_cli -i "${IFACE}" set_network "${ID}" psk "\"${PSK}\"" 2>&1 | grep -q "OK"
    RC=$((RC + $?))

    if [[ -n "${PRIORITY}" ]]; then
        if [[ "${PRIORITY}" -gt 0 ]]; then
            wpa_cli -i "${IFACE}" set_network "${ID}" priority "${PRIORITY}" 2>&1 | grep -q "OK"
        fi
    fi

    if [[ "${RC}" == 0 ]]; then
        wpa_cli -i "${IFACE}" enable_network "${ID}" 2>&1 | grep -q "OK"
    else
        wpa_cli -i "${IFACE}" remove_network "${ID}" 2>&1 | grep -q "OK"
        abort "failed to configure wireless network ${SSID}"
    fi

    wpa_cli -i "${IFACE}" save_config > /dev/null 2>&1

    wireless_list_interfaces | while read -r IFACE; do
        wpa_cli -i "${IFACE}" reconfigure > /dev/null 2>&1
    done

    return 0
}

# wireless_network_setup queries the user for an SSID and password
# and configures them via wpa_cli.
wireless_network_setup() {
    local IFACE
    IFACE="$(wireless_first_interface)"
    [[ -z "${IFACE}" ]] && abort "no wireless interface found"

    wireless_wpa_check "${IFACE}" || exit 1

    wireless_device_setup
    local RC=$?
    if [[ "${RC}" == 10 ]]; then
        report "wireless device regulatory config changed; please reboot and re-run script"
        exit 0
    elif [[ "${RC}" != 0 ]]; then
        abort "wireless device regulatory config failed, good luck!"
    fi

    report "adding low-priority wireless network for set-up..."
    wireless_add_network 0

    return 0
}

# wireless_list_networks returns the WPA ids for configured networks.
wireless_list_network_ids() {
    local IFACE
    IFACE="$(wireless_first_interface)"
    [[ -z "${IFACE}" ]] && abort "no wireless interface found"

    wpa_cli -i "${IFACE}" list_networks | tail -n +2 | cut -f 1
}

# wireless_describe_network $1=id returns a string with the network's
# priority, a colon, and the network's SSID. (e.g. 5:my_network)
wireless_describe_network() {
    local ID="$1"

    local IFACE
    IFACE="$(wireless_first_interface)"
    [[ -z "${IFACE}" ]] && abort "no wireless interface found"

    local PRIO
    PRIO="$(wpa_cli -i "${IFACE}" get_network "${ID}" priority)"
    if [[ "${PRIO}" == "FAIL" ]]; then
        return 1
    fi

    local SSID
    SSID="$(wpa_cli -i "${IFACE}" get_network "${ID}" ssid | tr -d '"')"

    echo "${PRIO}:${SSID}"
}
