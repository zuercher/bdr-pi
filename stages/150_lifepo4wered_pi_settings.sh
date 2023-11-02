#!/bin/bash

run_stage() {
    report "checking lifepo4wered defaults"

    local SETTINGS=(
        [VBAT_MIN]="2800"
        [VBAT_SHDN]="2850"
        [AUTO_SHDN_TIME]="20"
        [PI_BOOT_TO]="900"
    )

    local TO_UPDATE=()
    for KEY in "${!SETTINGS[@]}"; do
        EXPECTED="${SETTINGS[${KEY}]}"

        VALUE="$(lifepo4wered-cli get "${KEY}")"

        if [[ "${VALUE}" != "${EXPECTED}" ]]; then
            report "lifepo4wered ${KEY} is ${VALUE}, want ${EXPECTED}"
            TO_UPDATE+=("${KEY}")
        fi
    done

    if [[ "${#TO_UPDATE[@]}" -eq 0 ]]; then
        report "all lifepo4wered settings ok"
        return 0
    fi

    for KEY in "${TO_UPDATE[@]}"; do
        VALUE="${SETTINGS[${KEY}]}"
        report "setting lifepo4wered ${KEY} to ${VALUE}"

        lifepo4wered-cli set "${KEY}" "${VALUE}"
    done

    report "all lifepo4wered settings updated"
}
