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
    printf "%s\n" "$*" >/dev/stderr
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
    if [[ -n "${STAGE_NAME:-}" ]]; then
        printf "  %s: %s\n" "${STAGE_NAME}" "$*"
    else
        printf "%s\n" "$*"
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

# prompt_yesno $1...=prompt
#   prompts the user and returns their yes/no response
prompt_yesno() {
    local ANSWER

    read -er -p "$* [y/N]: " ANSWER
    case "$(echo "${ANSWER}" | tr '[:lower:]' '[:upper:]')" in
        Y|YES)
            echo "Y"
            ;;
        *)
            echo "N"
            ;;
    esac
}

# prompt_pw $1...=prompt
#   prompts the user with terminal echo disabled and returns their
#   response, which may be empty
prompt_pw() {
    local ANSWER

    read -ers -p "$*: " ANSWER
    echo "${ANSWER}"
}

# sed_inplace ...
#   runs sed with the given arguments and the appropriate "edit
#   in-place, no backup" flag for the OS. Mostly so we can test
#   on macOS.
sed_inplace() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
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

_SETUP_CONFIG_KEYS=()
_SETUP_CONFIG_VALUES=()
_SETUP_CONFIG_LOADED="false"

_write_config() {
    local FILE="${BDRPI_SETUP_CONFIG_FILE:-/boot/bdrpi-config.txt}"

    _load_config_once

    rm -f "${FILE}"
    touch "${FILE}"

    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        local KEY="${_SETUP_CONFIG_KEYS[IDX]}"
        local VALUE="${_SETUP_CONFIG_VALUES[IDX]}"

        echo "${KEY}=${VALUE}" >>"${FILE}"
    done
}

_load_config() {
    local FILE="${BDRPI_SETUP_CONFIG_FILE:-/boot/bdrpi-config.txt}"

    _SETUP_CONFIG_KEYS=()
    _SETUP_CONFIG_VALUES=()

    if ! [[ -s "${FILE}" ]]; then
        # missing or empty is ok
        return 0
    fi

    local LINE
    while IFS= read -r LINE; do
        local KEY="${LINE%=*}"

        if [[ "${KEY}" =~ ^[[:space:]]*# ]] || [[ -z "${KEY}" ]]; then
            continue
        fi

        local VALUE="${LINE#"${KEY}"=}"
        _SETUP_CONFIG_KEYS+=("${KEY}")
        _SETUP_CONFIG_VALUES+=("${VALUE}")
    done < "${FILE}"
}

_load_config_once() {
    if ! "${_SETUP_CONFIG_LOADED}"; then
        _load_config
        _SETUP_CONFIG_LOADED="true"
    fi
}

# clear all values and reset to initial state
reset_setup_config() {
    _SETUP_CONFIG_LOADED="false"
    _SETUP_CONFIG_KEYS=()
    _SETUP_CONFIG_VALUES=()
}

# set config value: $1=param-name, $2=value
set_setup_config() {
    local KEY="${1:-}"
    local VALUE="${2:-}"

    [[ -z "${KEY}" ]] && abort "cannot set config with empty config key"

    _load_config_once

    local FOUND=false
    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        if [[ "${_SETUP_CONFIG_KEYS[IDX]}" == "${KEY}" ]]; then
            _SETUP_CONFIG_VALUES[IDX]="${VALUE}"
            FOUND=true
            break
        fi
    done

    if ! "${FOUND}"; then
        _SETUP_CONFIG_KEYS+=("${KEY}")
        _SETUP_CONFIG_VALUES+=("${VALUE}")
    fi

    _write_config || abort "failed to update config"
}

# clear config key & value: $1=param-name
clear_setup_config() {
    local KEY="${1:-}"

    [[ -z "${KEY}" ]] && abort "cannot clear config with empty config key"

    _load_config_once

    local FOUND="false"
    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        if [[ "${_SETUP_CONFIG_KEYS[IDX]}" == "${KEY}" ]]; then
            _SETUP_CONFIG_KEYS[IDX]=""
            _SETUP_CONFIG_VALUES[IDX]=""
            FOUND="true"
            break
        fi
    done

    if "${FOUND}"; then
        _write_config || abort "failed to update config"
    fi

    return 0
}

# get config value: $1=param-name
get_setup_config() {
    local KEY="${1:-}"

    [[ -z "${KEY}" ]] && abort "cannot get empty config key"

    _load_config_once

    local VALUE=""
    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        if [[ "${_SETUP_CONFIG_KEYS[IDX]}" == "${KEY}" ]]; then
            VALUE="${_SETUP_CONFIG_VALUES[IDX]}"
            break
        fi
    done

    echo "${VALUE}"
}

# set an array key: $1=array-name, $2=index or "append", $3=value
set_setup_config_array() {
    local KEY="${1:-}"
    local INDEX="${2:-}"
    local VALUE="${3:-}"

    [[ -z "${KEY}" ]] && abort "cannot set empty config array key"
    [[ -z "${INDEX}" ]] && abort "cannot set config array without index"

    _load_config_once

    local ARRAYKEY=""
    if [[ "${INDEX}" != "append" ]]; then
        ARRAYKEY="${KEY}.${INDEX}"
        local FOUND=false
        for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
            if [[ "${_SETUP_CONFIG_KEYS[IDX]}" == "${ARRAYKEY}" ]]; then
                FOUND=true
                break
            fi
        done

        "${FOUND}" || abort "unable to ${KEY}[${INDEX}] -- not found"
    else
        # append
        local NEXT_INDEX
        NEXT_INDEX="$(get_setup_config_array_size "${KEY}")"

        ARRAYKEY="${KEY}.${NEXT_INDEX}"
    fi

    [[ -n "${ARRAYKEY}" ]] || abort "internal error computing array value key"

    set_setup_config "${ARRAYKEY}" "${VALUE}"
}

# get an array key: $1=array-name, $2=index
get_setup_config_array() {
    local KEY="${1:-}"
    local INDEX="${2:-}"

    [[ -z "${KEY}" ]] && abort "cannot get with empty config array key"
    [[ -z "${INDEX}" ]] && abort "cannot get config array without index"

    _load_config_once

    local ARRAYKEY="${KEY}.${INDEX}"
    get_setup_config "${ARRAYKEY}"
}

# get an array's size: $1=array-name
get_setup_config_array_size() {
    local KEY="${1:-}"

    [[ -z "${KEY}" ]] && abort "cannot get size with empty config array key"

    _load_config_once

    local LAST_INDEX="-1"
    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        if [[ "${_SETUP_CONFIG_KEYS[IDX]}" =~ ^${KEY}\.([0-9]+) ]]; then
            local THIS_INDEX="${BASH_REMATCH[1]}"
            if [[ ${THIS_INDEX} -gt ${LAST_INDEX} ]]; then
                LAST_INDEX="${THIS_INDEX}"
            fi
        fi
    done

    LAST_INDEX=$((LAST_INDEX+1))
    echo "${LAST_INDEX}"
}

# clear an array: $1=array-name
clear_setup_config_array() {
    local KEY="${1:-}"

    [[ -z "${KEY}" ]] && abort "cannot clear config with empty config array key"

    _load_config_once

    local FOUND="false"
    for IDX in "${!_SETUP_CONFIG_KEYS[@]}"; do
        if [[ "${_SETUP_CONFIG_KEYS[IDX]}" =~ ^${KEY}\.[0-9]+ ]]; then
            _SETUP_CONFIG_KEYS[IDX]=""
            _SETUP_CONFIG_VALUES[IDX]=""
            FOUND="true"
        fi
    done

    if "${FOUND}"; then
        _write_config || abort "failed to update config"

        # easier than mangling arrays
        reset_setup_config
    fi
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

if [[ "$(whoami)" == "root" ]]; then
    abort "run this as a normal user with access to sudo"
fi

BDR_DIR="${HOME}/.bdr-pi"
mkdir -p "${BDR_DIR}" || abort "could not create dir: ${BDR_DIR}"

REPO="https://github.com/zuercher/bdr-pi"
BDR_REPO_DIR="${HOME}/.bdr-pi/bdr-pi"

FIRST_BOOT=false
while [[ -n "${1:-}" ]]; do
    case "$1" in
        --first-boot)
            FIRST_BOOT=true
            shift
            ;;
        *)
            abort "usage: $0 [--first-boot]"
    esac
done

NEWTORK_OK=false
if ! "${FIRST_BOOT}"; then
    N=0
    NUM_ATTEMPTS=30
    while [[ "${N}" -lt "${NUM_ATTEMPTS}" ]]; do
        if network_can_reach "${REPO}"; then
            NETWORK_OK=true
            break
        fi

        N=$((N + 1))
        LEFT=$((NUM_ATTEMPTS - N))
        perror "unable to reach ${REPO}, will retry ${LEFT} more times..."
        sleep 1
    done

    if ! "${NETWORK_OK}"; then
        perror "failed to reach ${REPO}, starting wifi setup..."

        if "${FIRST_BOOT}"; then
            wireless_network_setup --first-boot
        else
            wireless_network_setup
        fi

        report "wireless setup complete; waiting for the internet to become reachable..."

        N=0
        NUM_ATTEMPTS=30
        while ! network_can_reach "${REPO}"; do
            N=$((N + 1))
            if [[ "${N}" -ge 60 ]]; then
                abort "failed to reach ${REPO} for 60 seconds, something's fucky"
            fi

            LEFT=$((NUM_ATTEMPTS - N))
            perror "unable to reach ${REPO}, will retry ${LEFT} more times..."
            sleep 1
        done
    fi
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

if [[ -d "${BDR_REPO_DIR}/.git" ]]; then
    # Git repository is present. Let's update it.
    push_dir "${BDR_REPO_DIR}"
    echo -n "${REPO} "
    git pull || abort "unable to pull $(git remote get-url origin)"
    pop_dir
else
    # No git repository. Clone it.
    git clone "${REPO}" "${BDR_REPO_DIR}" || abort "unable to clone ${REPO}"
    push_dir "${BDR_REPO_DIR}"
    # So it doesn't complain every time we pull
    git config pull.ff only
    pop_dir
fi

mkdir -p "${BDR_DIR}/state" || abort "could not create state dir"
mkdir -p "${BDR_DIR}/logs" || abort "could not create log dir"

SETUP_LOGFILE="${BDR_DIR}/logs/setup_$(date -u "+%Y%m%d_%H%M%S").log"

# Initial setup is complete, now transfer control to the code in BDR_REPO_DIR
# Jump through some hoops to set SETUP_FLUSH_PID with script's PID so we
# can send SIGUSR1 to it (which will flush logs). We also take care to
# pass along the original user's name, path and tty.
script --quiet --flush --log-out "${SETUP_LOGFILE}" \
       --command \
       "bash -c 'sudo \
            SETUP_USER=\"${USER}\" \
            SETUP_HOME=\"${HOME}\" \
            SETUP_TTY=\"$(tty)\" \
            SETUP_FLUSH_PID=\"\$PPID\" \
            BDR_REPO_DIR=\"${BDR_REPO_DIR}\" \
            BDR_DIR=\"${BDR_DIR}\" \
            \"${BDR_REPO_DIR}/update.sh\" $*'"
