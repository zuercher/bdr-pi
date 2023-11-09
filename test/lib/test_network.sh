#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_TEST_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/.. && pwd)"
_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/../.. && pwd)"

source "${_TEST_ROOT_DIR}/assertions.sh"
source "${_TEST_ROOT_DIR}/mocks.sh"

source "${_ROOT_DIR}/lib/network.sh"

export TEST_TMPDIR="${TMPDIR:-/tmp/}/bdrpi-test-network.$$"
export BDRPI_SYS_CLASS_NET="${TEST_TMPDIR}/sys/class/net"
export BDRPI_VAR_LIB_SYSTEMD_RFKILL="${TEST_TMPDIR}/var/lib/systemd/rfkill"
export BDRPI_SETUP_CONFIG_FILE="${TEST_TMPDIR}/setup_config.txt"

before_all() {
    mkdir -p "${BDRPI_SYS_CLASS_NET}/iface1/wireless"
    mkdir -p "${BDRPI_SYS_CLASS_NET}/iface2/not-wireless"
    mkdir -p "${BDRPI_SYS_CLASS_NET}/iface3/wireless"

    mkdir -p "${BDRPI_VAR_LIB_SYSTEMD_RFKILL}"
}

after_each() {
    rm -f "${BDRPI_SETUP_CONFIG_FILE}"

    clear_mocks
}

after_all() {
    rm -rf "${TEST_TMPDIR}"
}

test_wireless_list_interfaces() {
    assert_stdout_contains "iface1" wireless_list_interfaces
    assert_stdout_contains "iface3" wireless_list_interfaces
}

test_wireless_first_interface() {
    assert_stdout_contains "iface1" wireless_first_interface
}

test_wireless_reg_get_country() {
    mock_success_and_return iw "country US: stuff"

    assert_eq "$(wireless_reg_get_country)" "US"
    expect_mock_called_with_args "iw" "reg" "get"
}

test_wireless_reg_set_country() {
    mock_success iw

    assert_succeeds wireless_reg_set_country "GB"

    expect_mock_called_with_args "iw" "reg" "set" "GB"
}

test_wireless_wpa_check() {
    mock_success wpa_cli

    assert_succeeds wireless_wpa_check iface

    expect_mock_called_with_args "wpa_cli" "-i" "iface" "status"

    clear_mocks
    mock_error wpa_cli
    mock_success perror

    assert_fails wireless_wpa_check iface
}

test_wireless_wpa_get_country() {
    mock_success_and_return wpa_cli "US"

    assert_stdout_contains "US" wireless_wpa_get_country "iface"
    expect_mock_called_with_args "wpa_cli" "-i" "iface" "get" "country"
}

test_wireless_wpa_set_country() {
    mock_success wpa_cli

    assert_succeeds wireless_wpa_set_country "iface" "GB"
    expect_mock_called_with_args "wpa_cli" "-i" "iface" "set" "country" "GB"
}

test_wireless_disable_rfkill() {
    local RFKILL_FILE="${BDRPI_VAR_LIB_SYSTEMD_RFKILL}/foo:wlan"
    touch "${RFKILL_FILE}"

    mock_success installed
    mock_success rfkill
    mock_sudo

    assert_succeeds wireless_disable_rfkill
    expect_mock_called_with_args installed rfkill
    expect_mock_called_with_args rfkill unblock wifi

    assert_eq "$(cat "${RFKILL_FILE}")" "0"
}

test_wireless_disable_rfkill_missing_binary() {
    mock_error installed

    assert_succeeds wireless_disable_rfkill
}

test_wireless_device_setup_sets_country() {
    mock_success report
    mock_success_and_return wireless_first_interface "iface1"
    mock_success wireless_wpa_check
    mock_success_and_return wireless_wpa_get_country "GB"
    mock_success wireless_wpa_set_country
    mock_success_and_return wireless_reg_get_country "GB"
    mock_success wireless_reg_set_country
    mock_success wireless_disable_rfkill

    assert_exit_code 10 wireless_device_setup

    expect_mock_called_with_args wireless_wpa_get_country "iface1"
    expect_mock_called_with_args wireless_wpa_set_country "iface1" "US"
    expect_mock_called_with_args wireless_reg_set_country "US"
}

test_wireless_device_setup_with_preset_country() {
    mock_success report
    mock_success_and_return wireless_first_interface "iface1"
    mock_success wireless_wpa_check
    mock_success_and_return wireless_wpa_get_country "US"
    mock_success_and_return wireless_reg_get_country "US"
    mock_success wireless_disable_rfkill

    assert_succeeds wireless_device_setup
}

test_wireless_add_network() {
    mock_custom wpa_cli "-" <<'EOF'
        if [[ "$1" == "-i" ]]; then
            shift 2
        fi

        case "$1" in
            list_networks)
                echo "HEADER 1"
                echo "HEADER 2"
                echo $'EXISTING1\tEXISTING_SSID1\tblah'
                echo $'EXISTING2\tEXISTING_SSID2\tblah'
                ;;
            add_network)
                echo "NETWORKID1"
                ;;
            set_network)
                echo "OK"
                ;;
            enable_network)
                echo "OK"
                ;;
            remove_network)
                echo "OK"
                ;;
            save_config)
                ;;
            reconfigure)
                ;;
        esac
EOF

    assert_succeeds wireless_add_network SSID PSK

    expect_mock_called_with_args wpa_cli -i iface1 list_networks
    expect_mock_called_with_args wpa_cli -i iface1 add_network
    expect_mock_called_with_args wpa_cli -i iface1 set_network NETWORKID1 ssid "\"SSID\""
    expect_mock_called_with_args wpa_cli -i iface1 set_network NETWORKID1 psk "\"PSK\""
    expect_mock_called_with_args wpa_cli -i iface1 enable_network NETWORKID1
    expect_mock_called_with_args wpa_cli -i iface1 save_config
    expect_mock_called_with_args wpa_cli -i iface1 reconfigure
    expect_mock_called_with_args wpa_cli -i iface3 reconfigure

    clear_mock_calls

    # replace an existing SSID with 0 priority
    assert_succeeds wireless_add_network EXISTING_SSID1 PSK 0

    expect_mock_called_with_args wpa_cli -i iface1 list_networks
    expect_mock_called_with_args wpa_cli -i iface1 remove_network "EXISTING1"
    expect_mock_called_with_args wpa_cli -i iface1 add_network
    expect_mock_called_with_args wpa_cli -i iface1 set_network NETWORKID1 ssid "\"EXISTING_SSID1\""
    expect_mock_called_with_args wpa_cli -i iface1 set_network NETWORKID1 psk "\"PSK\""
    expect_mock_called_with_args wpa_cli -i iface1 enable_network NETWORKID1
    expect_mock_called_with_args wpa_cli -i iface1 save_config
    expect_mock_called_with_args wpa_cli -i iface1 reconfigure
    expect_mock_called_with_args wpa_cli -i iface3 reconfigure

    clear_mock_calls

    # add an SSID with priority
    assert_succeeds wireless_add_network SSID PSK 10

    expect_mock_called_with_args wpa_cli -i iface1 list_networks
    expect_mock_called_with_args wpa_cli -i iface1 add_network
    expect_mock_called_with_args wpa_cli -i iface1 set_network NETWORKID1 ssid "\"SSID\""
    expect_mock_called_with_args wpa_cli -i iface1 set_network NETWORKID1 psk "\"PSK\""
    expect_mock_called_with_args wpa_cli -i iface1 set_network NETWORKID1 priority "10"
    expect_mock_called_with_args wpa_cli -i iface1 enable_network NETWORKID1
    expect_mock_called_with_args wpa_cli -i iface1 save_config
    expect_mock_called_with_args wpa_cli -i iface1 reconfigure
    expect_mock_called_with_args wpa_cli -i iface3 reconfigure

    clear_mock_calls

    # replace an existing SSID
    assert_succeeds wireless_add_network EXISTING_SSID1 PSK 0
}

test_wireless_prompt_add_network() {
    mock_success report
    mock_success_and_return prompt "MY_SSID"
    mock_success_and_return prompt_pw "MY_PSK"
    mock_success wireless_add_network

    assert_succeeds wireless_prompt_add_network 0

    expect_mock_called_with_args wireless_add_network MY_SSID MY_PSK 0

    clear_mock_calls

    # add with priority
    assert_succeeds wireless_prompt_add_network 10

    expect_mock_called_with_args wireless_add_network MY_SSID MY_PSK 10
}

test_wireless_prompt_add_network_skippable() {
    mock_success report
    mock_success_and_return prompt ""

    assert_succeeds wireless_prompt_add_network 0 true
}

test_wireless_network_setup_preconfigured() {
    set_setup_config_array WIFI_SSID append "SSID1"
    set_setup_config_array WIFI_PASS append "PASS1"
    set_setup_config_array WIFI_PRIO append "10"
    set_setup_config_array WIFI_SSID append "SSID2"
    set_setup_config_array WIFI_PASS append "PASS2"
    set_setup_config_array WIFI_PRIO append "0"

    mock_success wireless_add_network

    assert_succeeds wireless_network_setup_preconfigured

    expect_mock_called_with_args "SSID1" "PASS1" 10
    expect_mock_called_with_args "SSID2" "PASS2" 0

    assert_eq "$(get_setup_config_array_size WIFI_SSID)" 0
}

test_wireless_network_setup_preconfigured_none() {
    # no setup config means it should do nothing and succeed
    assert_succeeds wireless_network_setup_preconfigured
}

test_wireless_network_setup() {
    mock_success wireless_wpa_check
    mock_success wireless_device_setup
    mock_success wireless_network_setup_preconfigured
    mock_success wireless_prompt_add_network
    assert_succeeds wireless_network_setup

    expect_mock_called_with_args wireless_wpa_check iface1
}

test_wireless_network_setup_skips_prompts() {
    set_setup_config WIFI_PERFORM_SSID_SETUP false

    mock_success wireless_wpa_check
    mock_success wireless_device_setup
    mock_success wireless_network_setup_preconfigured
    assert_succeeds wireless_network_setup

    expect_mock_called_with_args wireless_wpa_check iface1
}

test_wireless_network_setup_needs_reboot() {
    mock_success wireless_wpa_check
    mock_error wireless_device_setup 10

    assert_succeeds wireless_network_setup

    expect_mock_called_with_args wireless_wpa_check iface1
}

test_wireless_list_network_ids() {
    mock_success_and_return wpa_cli $'HEADER1\nHEADER2\nID1\tSSID1\tx\nID2\tSSID2\tx'

    assert_stdout_contains "ID1" wireless_list_network_ids
    assert_stdout_contains "ID2" wireless_list_network_ids

    expect_mock_called_with_args wpa_cli -i "iface1" list_networks
}

test_wireless_describe_network() {
    mock_custom wpa_cli "-" <<'EOF'
        if [[ "$1" == "-i" ]]; then
            shift 2
        fi

        case "$1" in
            get_network)
                case "${3:-}" in
                    priority)
                        echo "99"
                        ;;
                    ssid)
                        echo $'"SSID"'
                        ;;
                    *)
                        return 2
                        ;;
                esac
                ;;
            *)
                return 1
                ;;
        esac
EOF

    assert_stdout_contains "99:SSID" wireless_describe_network "ID"

    expect_mock_called_with_args wpa_cli -i iface1 get_network ID priority
    expect_mock_called_with_args wpa_cli -i iface1 get_network ID ssid
}

source "${_TEST_ROOT_DIR}/test-harness.sh"
