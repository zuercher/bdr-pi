#!/bin/bash

#{{begin_exclude}}#
if [[ -n "${_BOOT_CONFIG_SH_INCLUDED:-}" ]]; then
    return
fi
_BOOT_CONFIG_SH_INCLUDED=1
_BOOT_CONFIG_SH="${BASH_SOURCE[0]}"
_BOOT_CONFIG_LIB_DIR="$(cd "$(dirname "${_BOOT_CONFIG_SH}")" && pwd)"
source "${_BOOT_CONFIG_LIB_DIR}/io.sh"
source "${_BOOT_CONFIG_LIB_DIR}/reboot.sh"
#{{end_exclude}}#

_config_txt() {
    echo "${BDRPI_BOOT_CONFIG_TXT:-/boot/config.txt}"
}

# boot_config_contains_regex $1=section $2=regex returns success if
# /boot/config.txt contains a line matching regex within section
# marked by [section].
boot_config_contains_regex() {
    local SECTION="$1"
    local REGEX="$2"

    local MATCHING
    MATCHING="$(
        awk -v S="[${SECTION}]" \
            -v C='[all]' \
            '{
               if (substr($0, 0, 1) == "[") { C = $0 }
               else if (C == S) { print $0 }
             }' \
             "$(_config_txt)" | \
        grep -E "${REGEX}"
    )"

    [[ -n "${MATCHING}" ]]
}

# boot_config_contains $1=section $2=key $3=[value] checks if the
# /boot/config.txt contains the give key (or key=value) entry in the
# named section.
boot_config_contains() {
    local SECTION="$1"
    local KEY="$2"
    local VALUE=""
    if [[ $# -gt 2 ]]; then
        VALUE="$3"
    fi

    boot_config_contains_regex "${SECTION}" "^${KEY}=${VALUE}"
}

# boot_config_printf $1=section $...=printf-args checks if the last
# section in /boot/config.txt matches the given section. If not, it
# adds the section to the config. In any case, the remaining args are
# used with printf to adds lines to the config. Schedules a reboot on
# successful change.
boot_config_printf() {
    local SECTION="$1"
    shift

    local CONFIG_TXT="$(_config_txt)"
    touch "${CONFIG_TXT}"

    local LAST_SECTION
    LAST_SECTION="$(grep -E '^\[' "${CONFIG_TXT}" | tail -n 1)"
    if [[ "${LAST_SECTION}" != "[${SECTION}]" ]]; then
        printf "\n[%s]\n" "${SECTION}" >>"$(_config_txt)" || \
            abort "failed to add section ${SECTION} to ${CONFIG_TXT}"
    fi

    # shellcheck disable=SC2059
    printf "$@" >>"${CONFIG_TXT}" || abort "failed to append ${SECTION} to ${CONFIG_TXT}"

    reboot_required
}

# boot_config_replace $1=section $2=key $3=value sets the key to value
# in the given section of /boot/config.txt. Fails if the key is not
# already present in the section. Schedules a reboot on successful
# change.
boot_config_replace() {
    local SECTION="$1"
    local KEY="$2"
    local VALUE="$3"

    local CONFIG="$(_config_txt)"
    local BACKUP="$(_config_txt)~"

    if awk -v S="[${SECTION}]" \
           -v C='[all]' \
           -v K="${KEY}" \
           -v V="${VALUE}" \
           -v EC="1" \
           '{
              if (substr($0, 0, 1) == "[") {
                C = $0
                print $0
              } else if (C == S) {
                if (match($0, "^#?" K "=")) {
                  print K "=" V
                  EC = 0
                } else {
                  print $0
                }
              } else {
                print $0
              }
           }
           END { exit EC }' \
           "${CONFIG}" >"${BACKUP}"; then
        if mv "${BACKUP}" "${CONFIG}"; then
            reboot_required
            return 0
        fi
    fi

    abort "failed to replace key ${KEY} with ${VALUE} in section ${SECTION}"
}

# boot_config_set $1=section $2=key $3=value sets the key to value in
# the given section of /boot/config.txt. If the key does not exist in
# the given section, it is appended. Schedules a reboot if the file is
# changed.
boot_config_set() {
    local SECTION="$1"
    local KEY="$2"
    local VALUE="$3"

    if boot_config_contains "${SECTION}" "${KEY}" "${VALUE}"; then
        # Already set.
        report "boot config: ${KEY} already set to ${VALUE} in section ${SECTION}"
        return 0
    fi

    report "boot config: setting ${KEY} to ${VALUE} in section ${SECTION}"

    if boot_config_contains_regex "${SECTION}" "^#?${KEY}="; then
        # Has value, possibly commented out.
        boot_config_replace "${SECTION}" "${KEY}" "${VALUE}"
    else
        # No value, append it.
        boot_config_printf "${SECTION}" "%s=%s\n\n" "${KEY}" "${VALUE}"
    fi
}
