#!/bin/bash

#{{begin_exclude}}#
if [[ -n "${_REBOOT_SH_INCLUDED:-}" ]]; then
    return
fi
_REBOOT_SH_INCLUDED=1
_REBOOT_SH="${BASH_SOURCE[0]}"
_REBOOT_LIB_DIR="$(cd "$(dirname "${_REBOOT_SH}")" && pwd)"
source "${_REBOOT_LIB_DIR}/io.sh"
#{{end_exclude}}#

REBOOT_REQUIRED=false

# reboot_configured indicates if the user's bashrc has a reboot scheduled
reboot_configured() {
    local BASHRC="${SETUP_HOME}/.bashrc"
    grep -q "# BEGIN_ON_REBOOT VIA" "${BASHRC}"
}

# reboot_clear disables a scheduled reboot in the user's bashrc
reboot_clear() {
    local BASHRC="${SETUP_HOME}/.bashrc"

    if [[ ! -f "${BASHRC}" ]]; then
        abort "cannot clear reboot task without an existing ${BASHRC}"
    fi

    sed --in-place -e "/# BEGIN_ON_REBOOT VIA/,/# END_ON_REBOOT/d" "${BASHRC}" || \
        abort "failed to clear reboot handler in ${BASHRC}"
}

_on_reboot() {
    local BASHRC="${SETUP_HOME}/.bashrc"

    if [[ ! -f "${BASHRC}" ]]; then
        abort "cannot schedule reboot task without an existing ${BASHRC}"
    fi

    local TTYPE="terminal"
    if [[ "${SETUP_TTY}" =~ ^/dev/pts/.+ ]]; then
        # Some kind of pseudo-terminal (e.g. ssh), so expect the same for running on reboot.
        TTYPE="pseudo-terminal"
    fi

    if grep -q "# BEGIN_ON_REBOOT VIA ${TTYPE}" "${BASHRC}"; then
        # an on-reboot step is already scheduled.
        report "reboot already scheduled"
        return 0
    fi

    if reboot_configured; then
        # This on-reboot step is already scheduled but for a different terminal type,
        # so clear it.
        reboot_clear
    fi

    local MATCH="^${SETUP_TTY}$"
    local DESC="${SETUP_TTY}"
    if [[ "${TTYPE}" == "pseudo-terminal" ]]; then
        MATCH="^/dev/pts/.+"
        DESC="a pseudo-terminal"
    fi

    cat >>"${BASHRC}" << EOF
      # BEGIN_ON_REBOOT VIA ${TTYPE}
      if [[ "\$(tty)" =~ ${MATCH} ]]; then
        $@
      fi
      # END_ON_REBOOT
EOF

    report "scheduled reboot; logging in as ${SETUP_USER} on ${DESC} will resume configuration"

    REBOOT_REQUIRED=true
}

# reboot_required triggers a reboot and arranges for setup.sh to be
# run again on login.
reboot_required() {
    _on_reboot "\"${BDR_DIR}/setup.sh\""
}

# reboot_is_required indicates if a reboot is required
# (e.g. reboot_required was called).
reboot_is_required() {
    "${REBOOT_REQUIRED}"
}
