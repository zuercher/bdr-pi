#!/bin/bash

run_stage() {
    local PERFORM_SETUP="$(get_setup_config LIFEPO_PERFORM_SETUP)"
    if [[ -n "${PERFORM_SETUP}" ]] && [[ "${PERFORM_SETUP}" != "true" ]]; then
        report "skipping LiFePO4wered-Pi defaults, as instructed by image config"
        return 0
    fi

    report "checking lifepo4wered defaults"

    # PI_BOOT_TO controls how long the lifepo4wered will let
    # the pi run without communication.
    declare -A SETTINGS=(
        [VBAT_MIN]="2750"
        [VBAT_SHDN]="2850"
        [AUTO_SHDN_TIME]="3"
        [PI_BOOT_TO]="900"
        [AUTO_BOOT]=1
    )

    local UPDATED=false
    for KEY in "${!SETTINGS[@]}"; do
        local EXPECTED="${SETTINGS[${KEY}]}"

        local VALUE="$(lifepo4wered-cli get "${KEY}")"

        if [[ "${VALUE}" != "${EXPECTED}" ]]; then
            report "lifepo4wered ${KEY} is ${VALUE}, want ${EXPECTED}"

            lifepo4wered-cli set "${KEY}" "${EXPECTED}"

            UPDATED=true
        fi
    done

    if "${UPDATED}"; then
        report "all lifepo4wered settings updated"
    else
        report "all lifepow4ered sttings ok"
    fi
}
