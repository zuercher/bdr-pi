#!/bin/bash

run_stage() {
    perror "installing screen blanking daemon"

    install() {
        local SRC="$1"
        local TARGET="$2"

        if cp "${SRC}" "${TARGET}" && chown root:root "${TARGET}" && chmod 0755 "${TARGET}"; then
            return 0
        fi

        abort "error installing ${TARGET}"
    }

    local SCRIPT="${BDR_REPO_DIR}/resources/bdr_screenblank.sh"

    install "${SCRIPT}" /usr/local/bin/bdr_screenblank.sh

    local PERFORM_SETUP USE_FAKE
    PERFORM_SETUP="$(get_setup_config LIFEPO_PERFORM_SETUP)"
    if [[ -n "${PERFORM_SETUP}" ]] && [[ "${PERFORM_SETUP}" != "true" ]]; then
        perror "installing screen blanking systemd service with fake-lifepo4wered-cli"
        USE_FAKE=true
    else
        perror "installing screen blanking systemd service"
        USE_FAKE=false
    fi

    local SERVICE="${BDR_REPO_DIR}/resources/bdr_screenblank.service"

    if "${USE_FAKE}"; then
        local FAKE_SCRIPT="${BDR_REPO_DIR}/resources/fake-lifepo4wered-cli.sh"

        install "${FAKE_SCRIPT}" /usr/local/bin/fake-lifepo4wered-cli.sh

        sed -e '/^ExecStart=/ s@$@ --lifepo4wered-binary=/usr/local/bin/fake-lifepo4wered-cli.sh@' \
            "${SERVICE}" >/lib/systemd/system/bdr_screenblank.service
    else
        cp "${SERVICE}" /lib/systemd/system/bdr_screenblank.service
    fi

    if [[ -f "/lib/systemd/system/bdr_screenblank.service" ]] && \
           chown root:root /lib/systemd/system/bdr_screenblank.service && \
           chmod 0644 /lib/systemd/system/bdr_screenblank.service; then
        :
    else
        abort "error installing /lib/systemd/system/bdr_screenblank.service"
    fi

    systemctl daemon-reload

    systemctl enable bdr_screenblank.service || abort "error enabling service"
    systemctl start bdr_screenblank.service || abort "error starting service"
}
