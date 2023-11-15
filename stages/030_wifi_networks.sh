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

    # setup any images from the boot config (should be a no-op)
    wireless_newtork_setup_preconfigured

    local DEFAULT_PRIO_SSIDS=()
    local HIGH_PRIO_SSIDS=()
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
    done

    report "configured wireless networks:"
    report "  default priority:"
    if [[ "${#DEFAULT_PRIO_SSIDS[@]}" -gt 0 ]]; then
        for ID in "${DEFAULT_PRIO_SSIDS[@]}"; do
            report "    ${ID}"
        done
    else
        report "    <none>"
    fi

    report "  high priority:"
    if [[ "${#HIGH_PRIO_SSIDS[@]}" -gt 0 ]]; then
        for ID in "${HIGH_PRIO_SSIDS[@]}"; do
            report "    ${ID}"
        done
    else
        report "    <none>"
    fi

    local PERFORM_SETUP="$(get_setup_config WIFI_PERFORM_SSID_SETUP)"
    if [[ -n "${PERFORM_SETUP}" ]] && [[ "${PERFORM_SETUP}" != "true" ]]; then
        report "skipping wireless network prompts, as directed by image setup config"
        return 0
    fi

    echo "Note: use default priority SSIDs as backup networks (e.g. PAWDF wifi)"
    while true; do
        local RESP
        RESP="$(prompt_yesno Y "add a default priority SSID?")"
        if [[ "${RESP}" != "Y" ]]; then
            break
        fi

        wireless_prompt_add_network 0
    done

    echo "use high priority SSIDs as primary networks (e.g. the car's wifi)"
    while true; do
        local RESP
        RESP="$(prompt_yesno N "add a high priority SSID?")"
        if [[ "${RESP}" != "Y" ]]; then
            break
        fi

        wireless_prompt_add_network 10
    done
}
