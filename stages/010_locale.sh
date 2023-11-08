#!/bin/bash

run_stage() {
    local LOCALE="${BDRPI_LOCALE:-en_US.UTF-8}"

    report "setting locale to ${LOCALE}"

    local LOCALE_LINE
    if ! LOCALE_LINE="$(grep "^${LOCALE} " /usr/share/i18n/SUPPORTED)"; then
        abort "cannot find '${LOCALE}' in supported locales"
    fi

    local ENCODING
    ENCODING="$(echo "${LOCALE_LINE}" | cut -f2 -d " ")"

    echo "${LOCALE} ${ENCODING}" > /etc/locale.gen
    sed_inplace "s/^\s*LANG=\S*/LANG=${LOCALE}/" /etc/default/locale
    dpkg-reconfigure -f noninteractive locales || abort "failed to generate locales"

    export LANG="${LOCALE}"
}
