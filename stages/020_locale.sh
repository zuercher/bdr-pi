#!/bin/bash

run_stage() {
    local LOCALE="${BDRPI_WIFI_COUNTRY:-en_US.UTF-8}"

    local LOCALE_LINE
    if ! LOCALE_LINE="$(grep "^${LOCALE} " /usr/share/i18n/SUPPORTED)"; then
        abort "cannot find '${LOCALE}' in supported locales"
    fi

    local ENCODING
    ENCODING="$(echo "${LOCALE_LINE}" | cut -f2 -d " ")"

    echo "${LOCALE} ${ENCODING}" > /etc/locale.gen
    sed -i "s/^\s*LANG=\S*/LANG=${LOCALE}/" /etc/default/locale
    dpkg-reconfigure -f noninteractive locales
}
