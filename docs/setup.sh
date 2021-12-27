#!/bin/bash

# fail on unset variables
set -u


# push_dir <dir> invokes pushd and aborts the script on error.
push_dir() {
    pushd "${1}" >/dev/null || abort "could not change to ${1}"
}

# pop_dir invokes popd and aborts the script on error.
pop_dir() {
    popd >/dev/null || abort "could not pop dir"
}

# installed <app> returns success if the given app is on the PATH.
installed() {
    local BINARY="$1"
    hash "${BINARY}" 2> /dev/null
    return $?
}

# perror prints its arguments to stderr.
perror() {
    printf "%s\n" "$@" >/dev/stderr
    return 0
}

# abort prints its arguments and quits
abort() {
    perror "$@"
    exit 1
}

# report prints annotated stage output to stdout (or if no STAGE_NAME
# is set, just its arguments)
report() {
    if [[ -n "${STAGE_NAME}" ]]; then
        printf "  %s: %s\n" "${STAGE_NAME}" "$@"
    else
        printf "%s\n" "$@"
    fi
}

# prompt_default $1=default-value $2...=prompt
#   prompts the user and returns a default value if they provide no
#   reason
prompt_default() {
    local ANSWER
    local DEFAULT="$1"
    shift

    read -er -p "$* [${DEFAULT}]: " ANSWER
    if [ -z "${ANSWER}" ]; then
        ANSWER="${DEFAULT}"
    fi
    echo "${ANSWER}"
}

# prompt $1...=prompt
#   prompts the user and returns their response, which may be empty
prompt() {
    local ANSWER

    read -er -p "$*: " ANSWER
    echo "${ANSWER}"
}

# prompt_pw $1...=prompt
#   prompts the user with terminal echo disabled and returns their
#   response, which may be empty
prompt_pw() {
    local ANSWER

    read -ers -p "$*: " ANSWER
    echo "${ANSWER}"
}

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

    report "setting wireless country to ${COUNTRY}"

    local IFACE
    IFACE="$(wireless_first_interface)"
    [[ -z "${IFACE}" ]] && abort "no wireless interface found"

    wireless_wpa_check "${IFACE}" || exit 1

    if [[ "$(wireless_wpa_get_country "${IFACE}" )" != "${COUNTRY}" ]]; then
        wireless_wpa_set_country "${IFACE}" "${COUNTRY}"
    else
        report "wpa_cli country is already ${COUNTRY}, skipping"
    fi

    RC=0
    if [[ "$(wireless_reg_get_country)" != "${COUNTRY}" ]]; then
        wireless_reg_set_country "${COUNTRY}"
        # we need to reboot now, apparently
        RC=10
    else
        report "wireless device regulatory country is already ${COUNTRY}, skipping"
    fi

    wireless_disable_rfkill

    return ${RC}
}

# wireless_add_network [priority] adds a single SSID to the network configuration.
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

# wireless_network_setup queries the user for an SAID and password
# and configures them via wpa_cli.
wireless_network_setup() {
    local IFACE
    IFACE="$(wireless_first_interface)"
    [[ -z "${IFACE}" ]] && abort "no wireless interface found"

    wireless_wpa_check "${IFACE}" || exit 1

    wireless_device_setup
    local RC=$?
    if [[ "${RC}" == 10 ]]; then
        report "wireless device regulatory config changed; please reboot"
        exit 0
    elif [[ "${RC}" != 0 ]]; then
        abort "wireless device regulatory config failed, good luck!"
    fi

    wireless_add_network 0

    return 0
}

# Require bash
# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]; then
    abort "bash is required to interpret this script."
fi

OS="$(uname)"
if [[ "$OS" != "Linux" ]]; then
    abort "OS is ${OS} -- this isn't going to work out."
fi

DISTRIBUTION="$(lsb_release -si)"
if [[ "$DISTRIBUTION" != "Raspbian" ]]; then
    echo "Expected a Raspbian distribution, but we'll muddle on..."
fi

REPO="https://github.com/zuercher/bdr-pi"
BDR_DIR="${HOME}/.bdr-pi"

if ! network_can_reach "${REPO}"; then
    perror "error checking ${REPO}, starting wifi setup..."
    wireless_network_setup

    N=0
    while ! network_can_reach "${REPO}"; do
        N=$((N + 1))
        if [[ "${N}" -ge 60 ]]; then
            abort "been waiting for ${SSID} for 60 seconds, something's fucky"
        fi

        report "still cannot reach ${REPO}"
        sleep 1
    done
fi

# Check if git is installed.
if ! installed git; then
    # Nope. Tallyho!
    echo "installing git"
    sudo apt-get -y install git
    hash -r

    if ! installed git; then
        abort "tried to install git, but still can't find it on the path"
    fi
fi

REPO="https://github.com/zuercher/bdr-pi"
BDR_DIR="${HOME}/.bdr-pi"
if [[ -d "${BDR_DIR}/.git" ]]; then
    # Git repository is present. Let's update it.
    push_dir "${BDR_DIR}"
    echo -n "${REPO} "
    git pull || abort "unable to pull $(git remote get-url origin)"
    pop_dir
else
    # No git repository. Clone it.
    git clone "${REPO}" "${BDR_DIR}" || abort "unable to clone ${REPO}"
    push_dir "${BDR_DIR}"
    # So it doesn't complain every time we pull
    git config pull.ff only
    pop_dir
fi

mkdir -p "${BDR_DIR}/state" || abort "could not create state dir"

# Initial setup is complete, now transfer control to the code in BDR_DIR
sudo SETUP_USER="${USER}" SETUP_HOME="${HOME}" BDR_DIR="${BDR_DIR}" "${BDR_DIR}/update.sh" "$@"
