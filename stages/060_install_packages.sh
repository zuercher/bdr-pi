#!/bin/bash

run_stage() {
    report "updating apt repo and upgrading installed packages"

    apt-get update || abort "unable to update apt repositories"

    apt-get upgrade -y || abort "unable to update installed packages"

    report "installing additional packages for racecapture"

    local PKGS=(
        mesa-utils
        libgles2
        libegl1-mesa
        libegl-mesa0
        mtdev-tools
    )
    apt-get install -y "${PKGS[@]}" || abort "unable to install packages: ${PKGS[*]}"
}

