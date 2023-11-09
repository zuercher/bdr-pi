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
source "${_NETWORK_LIB_DIR}/setup_config.sh"
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
    for dir in "${BDRPI_SYS_CLASS_NET:-/sys/class/net}"/*/wireless; do
        if [ -d "$dir" ]; then
            basename "$(dirname "$dir")"
        fi
    done | sort
}

# wireless_first_interface returns the first entry from
# wireless_list_interfaces.
wireless_first_interface() {
    wireless_list_interfaces | head -n 1
}

# wireless_reg_get_country reports the regulatory country that the
# wireless chipset reports.
wireless_reg_get_country() {
    iw reg get | sed -n -E -e "s/country ([A-Z]+):.*/\1/p"
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
        for filename in "${BDRPI_VAR_LIB_SYSTEMD_RFKILL:-/var/lib/systemd/rfkill}"/*:wlan; do
            # This may be run from setup.sh at which point we're not root, so
            # use sudo to make sure the write succeeds.
            echo 0 | sudo tee "${filename}" >/dev/null
        done
    fi
}

# wireless_device_setup attempts to setup wireless networking. Error
# code 10 indicates a reboot is required. Defaults to US regulatory
# networking unless BDRPI_WIFI_COUNTRY is set or if a value is set
# in the setup config file.
wireless_device_setup() {
    local COUNTRY="${BDRPI_WIFI_COUNTRY:-US}"

    local SETUP_CONFIG_COUNTRY
    SETUP_CONFIG_COUNTRY="$(get_setup_config WIFI_COUNTRY)"
    if [[ -n "${SETUP_CONFIG_COUNTRY}" ]]; then
        COUNTRY="${SETUP_CONFIG_COUNTRY}"
    fi

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

    local RC=0
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

# wireless_add_network $1=SSID $2=PSK $3=prioritypriority adds a
# single SSID to the network configuration.
wireless_add_network() {
    local SSID="${1}"
    local PSK="${2}"
    local PRIORITY="${3:-}"

    local IFACE
    IFACE="$(wireless_first_interface)"
    [[ -z "${IFACE}" ]] && abort "no wireless interface found"

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

# wireless_prompt_add_network $1=priority $2=[skippable] prompts for
# and adds a single SSID to the network configuration with the given
# priority (0 is lowest). If any second argument is given, it accepts
# an empty SSID and returns success if none is given.
wireless_prompt_add_network() {
    local PRIORITY="$1"
    local SKIPPABLE=false
    local SSID_PROMPT="Wireless SSID"
    if [[ $# -gt 1 ]]; then
        SKIPPABLE=true
        SSID_PROMPT="Wireless SSID (empty to skip)"
    fi
    local SSID=""
    while [[ -z "${SSID}" ]]; do
        SSID=$(prompt "${SSID_PROMPT}")
        if "${SKIPPABLE}" && [[ -z "${SSID}" ]]; then
            report "trying to continue with existing network config, good luck!"
            return 0
        fi
    done
    local PSK=""
    while [[ -z "${PSK}" ]]; do
        PSK=$(prompt_pw "Wireless passphrase for ${SSID}")
        echo
    done

    wireless_add_network "${SSID}" "${PSK}" "${PRIORITY}"
}

# wireless_network_setup_preconfigured iterates over pre-configured
# networks in the image setup config and configures them. When
# completed, it removes the networks from the image config.
wireless_network_setup_preconfigured() {
    local NUM_CONFIGS
    NUM_CONFIGS="$(get_setup_config_array_size WIFI_SSID)"
    if [[ -z "${NUM_CONFIGS}" ]] || [[ "${NUM_CONFIGS}" -eq 0 ]]; then
        return 0
    fi

    local IDX=0
    while [[ "${IDX}" -lt "${NUM_CONFIGS}" ]]; do
        local SSID PASS PRIO
        SSID="$(get_setup_config_array WIFI_SSID "${IDX}")"
        PASS="$(get_setup_config_array WIFI_PASS "${IDX}")"
        PRIO="$(get_setup_config_array WIFI_PRIO "${IDX}")"

        wireless_add_network "${SSID}" "${PASS}" "${PRIO}" || abort "failed to setup ${SSID}"
        IDX=$((IDX+1))
    done

    clear_setup_config_array WIFI_SSID
    clear_setup_config_array WIFI_PASS
    clear_setup_config_array WIFI_PRIO
}

# wireless_network_setup queries the user for an SSID and password and
# configures them via wpa_cli. Wireless network config is loaded from
# the boot setup, if found.
wireless_network_setup() {
    local IFACE
    IFACE="$(wireless_first_interface)"
    [[ -z "${IFACE}" ]] && abort "no wireless interface found"

    wireless_wpa_check "${IFACE}" || exit 1

    wireless_device_setup
    local RC=$?
    if [[ "${RC}" -eq 10 ]]; then
        report "wireless device regulatory config changed; please reboot and re-run script"
        exit 0
    elif [[ "${RC}" -ne 0 ]]; then
        abort "wireless device regulatory config failed, good luck!"
    fi

    wireless_network_setup_preconfigured

    local PERFORM_SETUP
    PERFORM_SETUP="$(get_setup_config WIFI_PERFORM_SSID_SETUP)"
    if [[ -z "${PERFORM_SETUP}" ]] || [[ "${PERFORM_SETUP}" == "true" ]]; then
        report "adding low-priority wireless network for set-up..."
        wireless_prompt_add_network 0 skippable
    else
        report "skipping wireless network prompts, as directed by image setup config"
    fi

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
