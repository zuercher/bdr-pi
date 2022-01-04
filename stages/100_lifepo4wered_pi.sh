#!/bin/bash

run_stage() {
    report "installing additional packages for LiFePO4wered-Pi"

    local PKGS=(
        build-essential
        libsystemd-dev
    )
    apt-get install -y "${PKGS[@]}" || abort "unable to install packages: ${PKGS[*]}"

    local UPS_DIR="${SETUP_HOME}/lifepo4wered-pi"
    local UPS_REPO="https://github.com/xorbit/LiFePO4wered-Pi.git"

    # clone and build as the setup user for permissions reasons
    sudo -u "${SETUP_USER}" git clone "${UPS_REPO}" "${UPS_DIR}" || \
        abort "failed to clone ${UPS_REPO}"

    push_dir "${UPS_DIR}"

    sudo -u "${SETUP_USER}" make all || abort "lifepo4wered-pi build failed"

    make user-install || abort "lifepo4wered-pi install failed"

    pop_dir
}
