#!/bin/bash

run_stage() {
    [ ! -e /boot/overlays/vc4-kms-v3d.dtbo ] && abort "missing opengl driver/kernel, please update"

    local PKGS=(gldriver-test libgl1-mesa-dri)
    apt-get install -y "${PKGS[@]}" || abort "unable to install opengl packages: ${PKGS[*]}"

    local CONFIG="/boot/config.txt"

    if sed -n "/\[pi4\]/,/\[/ !p" "${CONFIG}" | grep -q "^dtoverlay=vc4-kms-v3d" ; then
        report "OpenGL desktop driver with KMS already selected, skipping"
        return 0
    fi

    report "Configuring OpenGL desktop driver with KMS"

    # disable the fkms version
    sed "${CONFIG}" -i -e "s/^dtoverlay=vc4-fkms-v3d/#dtoverlay=vc4-fkms-v3d/g"

    # enable the one we want, if it's commented out
    sed "${CONFIG}" -i -e "s/^#dtoverlay=vc4-kms-v3d/dtoverlay=vc4-kms-v3d/g"

    # otherwise, explicitly add it
    if ! sed -n "/\[pi4\]/,/\[/ !p" "${CONFIG}" | grep -q "^dtoverlay=vc4-kms-v3d" ; then
        printf "[all]\ndtoverlay=vc4-kms-v3d\n" >> "${CONFIG}"
    fi

    reboot_required
}
