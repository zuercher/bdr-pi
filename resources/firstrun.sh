#!/bin/bash

[[ -z "${BDRPI_CONFIG}" ]] && BDRPI_CONFIG="/boot/bdrpi-config.txt"
[[ -z "${BDRPI_SETUP_SH}" ]] && BDRPI_CONFIG="/boot/bdrpi-setup.sh"
[[ -z "${BDRPI_LOG}" ]] && BDRPI_CONFIG="/boot/bdrpi.log"

logger() {
    local MSG="$*"

    echo "${MSG}" >>"${BDRPI_LOG}"
    echo "${MSG}"
}

abort() {
    local MSG="$*"

    # something bad happened, don't cleanup
    trap - EXIT

    logger "FATAL: ${MSG}"

    # give the user some time to read the error
    sleep 10

    exit 1
}

cleanup() {
    # disable running this script on boot
    sed_inplace 's/ systemd.run.*//g' /boot/cmdline.txt

    # clean ourselves up
    rm -f /boot/bdrpi-firstrun.sh

    logger "completed $0"
}
trap cleanup EXIT

sed_inplace() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

getconfig() {
    grep -E "^${1}=" "${BDRPI_CONFIG}" | tail -n 1 | cut -d= -f2-
}

configure_user() {
    local USER="$1"
    local PASS="$2"

    local FIRST_USER
    FIRST_USER="$(getent passwd 1000 | cut -d: -f1)"
    if [[ -z "${FIRSTUSER}" ]]; then
        # No user to rename...
        abort "unable to find first user for rename (falling back to userconfig service)"
    fi

    # rename user (as in /usr/lib/userconfig-pi/userconfig)
    if [[ "${FIRST_USER}" != "${USER}" ]]; then
        # rename user
        logger "rename ${FIRST_USER} to ${USER}"

        local FIRST_GROUP
        FIRST_GROUP="$(getent group 1000 | cut -d: -f1)"

        usermod -l "${USER}" "${FIRST_USER}"
        usermod -m -d "/home/${USER}" "${USER}"
        groupmod -n "${USER}" "${FIRST_GROUP}"
        local F
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
    logger "change user password"
    echo "${USER}:${PASS}" | chpasswd

    # delete the password from the config
    logger "remove user password from setup config"
    sed_inplace -E -e "/^FIRST_RUN_PASS=.*/d"
}

logger "starting $0"

# create user with PW from /boot/bdrpi-config.txt
USER="$(getconfig FIRST_RUN_USER)"
if [[ -z "${USER}" ]]; then
    USER="pi"
    logger "defaulting to user 'pi'"
fi

PASS="$(getconfig FIRST_RUN_PASS)"
if [[ -n "${PASS}" ]]; then
    logger "configuring user ${USER}"
    configure_user "${USER}" "${PASS}"
fi

# copy /boot/bdr-setup.sh to /home/$USER
if [[ ! -f "/home/${USER}/setup.sh" ]]; then
    logger "copying setup script to user home"
    cp "${BDRPI_SETUP_SH}" "/home/${USER}/setup.sh" || \
        abort "failed to copy ${BDRPI_SETUP_SH}"
fi

# append start code to /home/$USER/.bashrc
if ! grep -q "BEGIN_ON_REBOOT" "/home/${USER}/.bashrc"; then
    logger "configuring autolaunch of setup script for ${USER}"
    cat >>"/home/${USER}/.bashrc" << EOF
      # BEGIN_ON_REBOOT
      /home/${USER}/setup.sh
      # END_ON_REBOOT
EOF
fi

# configure autologin
logger "configuring autologin for ${USER}"
ln -fs \
   /lib/systemd/system/getty@.service \
   /etc/systemd/system/getty.target.wants/getty@tty1.service
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER} --noclear %I \$TERM
EOF

# setup wireless iface
DESIRED_COUNTRY="$(getconfig WIFI_COUNTRY)"
DESIRED_COUNTRY="${DESIRED_COUNTRY:-US}"

logger "configuring wifi hardware..."
COUNTRY="$(iw reg get | sed -n -E -e "s/country ([A-Z]+):.*/\1/p")"
logger "  country is ${COUNTRY}"
if [[ "${COUNTRY}" != "${DESIRED_COUNTRY}" ]]; then
    logger "  set countrhy to ${DESIRED_COUNTRY}"
    iw reg set "${DESIRED_COUNTRY}" 2> /dev/null
fi

exit 0
