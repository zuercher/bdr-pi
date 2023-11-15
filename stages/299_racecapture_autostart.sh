#!/bin/bash

run_stage() {
    local AUTOSTART
    AUTOSTART="$(get_setup_config RACECAPTURE_AUTOLAUNCH)"

    report "preparing racecapture launch script"

    local FILE="bdr_racecapture.sh"
    local SCRIPT_TMPL="${BDR_REPO_DIR}/resources/${FILE}"
    local SCRIPT_TARGET="${SETUP_HOME}/${FILE}"

    local ESCAPED_HOME="${SETUP_HOME//\//\\\/}"

    if ! sed -e "s/{{SETUP_HOME}}/${ESCAPED_HOME}/g" "${SCRIPT_TMPL}" >"${SCRIPT_TARGET}"; then
        abort "error preparing ${SCRIPT_TARGET}"
    fi

    chown "${SETUP_USER}:${SETUP_USER}" "${SCRIPT_TARGET}"
    chmod a+x "${SCRIPT_TARGET}"

    if [[ "${AUTOSTART}" == "false" ]]; then
        report "not enabling auto-start of racecapture, as directed by image config"
        return 0
    fi

    report "enabling auto-start of racecapture"

    local BASHRC="${SETUP_HOME}/.bashrc"

    local START_FLAG="BEGIN_RCAP_START"
    local END_FLAG="END_RCAP_START"
    if grep -q "# ${START_FLAG}:" "${BASHRC}"; then
        sed_inplace -e "/# ${START_FLAG}:/,/# ${END_FLAG}/d" "${BASHRC}" || \
            abort "failed to clear old start handler in ${BASHRC}"
    fi

    sed -e 's/^ \{6\}//' >>"${BASHRC}" << EOF

      # ${START_FLAG}: start racecapture on login from tty1
      if [[ "\$(tty)" == "/dev/tty1" ]]; then
        echo
        if ! read -t 3 -p "starting racecapture in 3s (press ENTER to abort) "; then
          printf "\nsend it!\n"
          "${SCRIPT_TARGET}"
        fi
      fi
      # ${END_FLAG}
EOF

    report "configured execution of racecapture on login to /dev/tty1"
}
