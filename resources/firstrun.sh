#!/bin/bash

logger "starting $0"

[[ -z "${BDRPI_CONFIG}" ]] && BDRPI_CONFIG="/boot/bdrpi-config.txt"
[[ -z "${BDRPI_SETUP_SH}" ]] && BDRPI_CONFIG="/boot/bdrpi-setup.sh"

sed_inplace() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

cleanup() {
    # disable running this script on boot
    sed_inplace 's/ systemd.run.*//g' /boot/cmdline.txt

    # clean ourselves up
    rm -f /boot/bdrpi-firstrun.sh

    logger "completed $0"
}
trap cleanup EXIT

abort() {
    logger -p user:error "$*"
    exit 1
}

getconfig() {
    grep -E "^FIRST_RUN_${1}=" "${BDRPI_CONFIG}" | tail -n 1 | cut -d= -f2-
}

# create user with PW from /boot/bdrpi-config.txt
USER="$(getconfig USER)"
if [[ -z "${USER}" ]]; then
    USER="pi"
    logger "defaulting to user 'pi'"
fi
USER="$(getconfig PASS)"
if [[ -z "${PASS}" ]]; then
    PASS="pi"
    logger -p user:warning "using default password"
fi

FIRST_USER="$(getent passwd 1000 | cut -d: -f1)"
if [[ -z "${FIRSTUSER}" ]]; then
    # No user to rename...
    abort "unable to find first user for rename (falling back to userconfig service)"
fi

# rename user (as in /usr/lib/userconfig-pi/userconfig)
if [[ "${FIRST_USER}" != "${USER}" ]]; then
    # rename user
    logger "rename ${FIRST_USER} to ${USER}"

    FIRST_GROUP="$(getent group 1000 | cut -d: -f1)"

    usermod -l "${USER}" "${FIRST_USER}"
    usermod -m -d "/home/${USER}" "${USER}"
    groupmod -n "${USER}" "${FIRST_GROUP}"
    for F in /etc/subuid /etc/subgid; do
        sed_inplace "s/^${FIRST_USER}:/${USER}:/" "${F}"
    done
    if [ -f /etc/sudoers.d/010_pi-nopasswd ]; then
        sed_inplace "s/^${FIRST_USER} /${USER} /" /etc/sudoers.d/010_pi-nopasswd
    fi
fi

# as in /usr/lib/userconfig-pi/userconfig
logger "cancel user-service rename"
/usr/bin/cancel-rename "${USER}"

# disable userconfig.service
logger "cancel user-service rename"
systemctl stop userconfig
systemctl disable userconfig
systemctl mask userconfig || abort "unable to mask userconfig"

# change passwd (as in as in /usr/lib/userconfig-pi/userconfig-service)
echo "${USER}:${PASS}" | chpasswd

# copy /boot/bdr-setup.sh to /home/$USER
cp "${BDRPI_SETUP_SH}" "/home/${USER}/setup.sh" || \
    abort "failed to copy ${BDRPI_SETUP_SH}"

# append start code to /home/$USER/.bashrc
cat >>"/home/${USER}/.bashrc" << EOF
      # BEGIN_ON_REBOOT
      /home/${USER}/setup.sh
      # END_ON_REBOOT
EOF

# configure autologin
ln -fs \
   /lib/systemd/system/getty@.service \
   /etc/systemd/system/getty.target.wants/getty@tty1.service
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER} --noclear %I \$TERM
EOF

exit 0
