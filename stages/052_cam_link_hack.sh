#!/bin/bash

run_stage() {
    local CONFIG="/boot/config.txt"

    if grep -q -F "[EGA_Cam_Link_4K]" "${CONFIG}"; then
        return 0
    fi

    report "Configuring output mode for Cam Link 4K..."

    # Force 800x600 resolution.
    printf "\n[EGA_Cam_Link_4K]\nhdmi_group=2\nhdmi_mode=9\nhdmi_force_mode=1\n\n[all]\n" >> "${CONFIG}"

    reboot_required
}
