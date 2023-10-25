#!/bin/bash

run_stage() {
    local GPU_MEM="${BDRPI_GPU_MEM:-256}"

    # Disable pi logo, console blanking, and the splash screen
    if ! grep -q "logo\.nologo" /boot/cmdline.txt; then
        report "disabling boot logo"

        sed -i '1 s/$/ logo.nologo/' /boot/cmdline.txt
    fi

    if ! grep -q "consoleblank=0" /boot/cmdline.txt; then
        report "disabling console blanking"

        sed -i '1 s/$/ consoleblank=0/' /boot/cmdline.txt
    fi

    boot_config_set "all" "disable_splash" "1"
    boot_config_set "all" "disable_touchscreen" "1"
    boot_config_set "all" "gpu_mem" "${GPU_MEM}"
}
