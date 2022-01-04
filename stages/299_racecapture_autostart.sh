#!/bin/bash

run_stage() {
    report "enabling auto-start of racecapture"

    local FILE="bdr_racecapture.sh"
    local SCRIPT_TMPL="${BDR_DIR}/resources/${FILE}"
    local SCRIPT_TARGET="${SETUP_HOME}/${FILE}"

    if ! sed -e "s/{{SETUP_HOME}}/${SETUP_HOME}/g" "${SCRIPT_TMPL}" >"${SCRIPT_TARGET}"; then
        abort "error preparing ${SCRIPT_TARGET}"
    fi

    local BASHRC="${SETUP_HOME}/.bashrc"

    sed -e 's/^[[:space:]]*//' >>"${BASHRC}" << EOF
      # start recapture on login from tty0
      if [[ "\$(tty)" == "/dev/tty1" ]]; then
        "${SCRIPT_TARGET}"
      fi
EOF

    report "configured execution of racecapture on login to /dev/tty1"
}
