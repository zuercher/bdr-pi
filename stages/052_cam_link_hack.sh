#!/bin/bash

run_stage() {
    if boot_config_contains "EGA_Cam_Link_4K" "hdmi_group" "2" && \
            boot_config_contains "EGA_Cam_Link_4K" "hdmi_mode" "9" && \
            boot_config_contains "EGA_Cam_Link_4K" "hdmi_force_mode" "1"; then
        report "output mode for Cam Link 4K already set"
        return 0
    fi

    boot_config_printf "EGA_Cam_Link_4K" "hdmi_group=2\nhdmi_mode=9\nhdmi_force_mode=1\n"
}
