#!/bin/bash

run_stage() {
    report "updating apt repo and upgrading installed packages"

    apt-get update -q -y || abort "unable to update apt repositories"

    apt-get upgrade -q -y || abort "unable to update installed packages"

    apt-get install -q -y \
            curl \
            mesa-utils \
            libgles2 \
            libegl1-mesa \
            libegl-mesa0 \
            mtdev-tools \
            pmount \
            wget
}
