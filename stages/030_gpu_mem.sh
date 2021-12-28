#!/bin/bash

run_stage() {
    report "setting gpu_mem to 256 MB"

    sed -i "s/^gpu_mem=[0-9]\+$/gpu_mem=256/" /boot/config.txt

    reboot_required
}
