#!/bin/bash

run_stage() {
    RC_VERSION="${BDRPI_RACECAPTURE_VERSION:-2.2.0}"
    RC_FILE="${BDRPI_RACECAPTURE_FILE:-racecapture_linux_raspberrypi_${RC_VERSION}.tar.bz2}"
    RC_URL="${BDRPI_RACECAPTURE_URL:-https://autosportlabs-software.s3-us-west-2.amazonaws.com/${RC_FILE}}"

    report "installing additional packages for racecapture"

    local PKGS=(
        mesa-utils
        libgles2
        libegl1-mesa
        libegl-mesa0
        mtdev-tools
        wget
    )
    apt-get install -y "${PKGS[@]}" || abort "unable to install packages: ${PKGS[*]}"

    # perform these actions as the setup user to keep the permissions correct
    sudo -u "${SETUP_USER}" wget "${RC_URL}" || abort "unable to download ${RC_URL}"
    sudo -u "${SETUP_USER}" tar xfJ "${RC_FILE}" || abort "unable to extract ${RC_FILE}"

    [[ -d "${SETUP_HOME}/racecapture" ]] || abort "missing ${SETUP_HOME}/racecapture directory"
}
