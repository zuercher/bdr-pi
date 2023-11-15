#!/bin/bash

run_stage() {
    local ROTATE_DISPLAY="$(get_setup_config DISPLAY_ROTATE)"

    if [[ "${ROTATE_DISPLAY}" == "180" ]]; then
        report "rotating display 180"

        sed_inplace '1 s/$/ video=DSI-1:800x480@60,rotate='"${ROTATE_DISPLAY}"'/' /boot/cmdline.txt

        reboot_required
    elif [[ -n "${ROTATE_DISPLAY}" ]]; then
        abort "ROTATE_DISPLAY is ${ROTATE_DISPLAY}, but I don't know how to do that."
    fi
}
