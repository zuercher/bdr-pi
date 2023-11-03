#!/bin/bash

run_stage() {
    report "checking lifepo4wered defaults"

    declare -A SETTINGS=(
        [VBAT_MIN]="2800"
        [VBAT_SHDN]="2850"
        [AUTO_SHDN_TIME]="20"
        [PI_BOOT_TO]="900"
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
