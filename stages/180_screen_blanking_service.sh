#!/bin/bash

run_stage() {
    perror "installing screen blanking daemon"

    local SCRIPT="${BDR_REPO_DIR}/resources/bdr_screenblank.sh"

    cp "${SCRIPT}" /usr/local/bin/bdr_screenblank.sh || abort "error copying script"
    chown root:root /usr/local/bin/bdr_screenblank.sh || abort "error changing script ownership"
    chmod 0755 /usr/local/bin/bdr_screenblank.sh || abort "error changing script permissions"


    local PERFORM_SETUP="$(get_setup_config LIFEPO_PERFORM_SETUP)"
    if [[ -n "${PERFORM_SETUP}" ]] && [[ "${PERFORM_SETUP}" != "true" ]]; then
        report "skipping screen blanking service, since lifepo4wered-cli wasn't installed"
        return 0
    fi

    perror "installing screen blanking systemd service"

    local SERVICE="${BDR_REPO_DIR}/resources/bdr_screenblank.service"
    cp "${SERVICE}" /lib/systemd/system/bdr_screenblank.service || abort "error copying service"
    chown root:root /lib/systemd/system/bdr_screenblank.service || abort "error changing service ownership"
    chmod 0644 /lib/systemd/system/bdr_screenblank.service || abort "error changing service permissions"

    systemctl daemon-reload

    systemctl enable bdr_screenblank.service || abort "error enabling service"
    systemctl start bdr_screenblank.service || abort "error starting service"
}
