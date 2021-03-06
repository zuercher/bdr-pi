#!/bin/bash

run_stage() {
    [ ! -e /boot/overlays/vc4-kms-v3d.dtbo ] && abort "missing opengl driver/kernel, please update"

    local PKGS=(gldriver-test libgl1-mesa-dri)
    apt-get install -q -y "${PKGS[@]}" || abort "unable to install opengl packages: ${PKGS[*]}"

    boot_config_set "all" "dtoverlay" "vc4-kms-v3d"

    reboot_required
}
