#!/bin/bash

run_stage() {

    if grep -q -E "^gpu_mem=256$" /boot/config.txt; then
        report "gpu_mem already set to 256 MB, skipping"
        return 0
    fi

    report "setting gpu_mem to 256 MB"
    sed -i "s/^gpu_mem=[0-9]\+$/gpu_mem=256/" /boot/config.txt

    reboot_required
}
