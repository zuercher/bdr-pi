#!/bin/bash

is_boot_cli() {
    if systemctl get-default | grep -q multi-user; then
        # Set to boot multi-user
        return 0
    fi

    # something else, probably desktop
    return 1
}

run_stage() {
    if [[ "${SETUP_USER}" == "root" ]]; then
        report "skipping auto-login since the setup user is root"
        return 0
    fi

    if ! is_boot_cli; then
        report "default to multi-user.target"
        systemctl set-default multi-user.target
    fi

    report "configure autologin for ${SETUP_USER}"
    ln -fs /lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${SETUP_USER} --noclear %I \$TERM
EOF

    report "autologin will take effect after the next reboot"
}
