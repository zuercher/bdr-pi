#!/bin/bash

run_stage() {
    # Disable pi logo, console blanking, and the splash screen
    if ! grep -q "logo\.nologo" /boot/firmware/cmdline.txt; then
        report "disabling boot logo"

        sed_inplace '1 s/$/ logo.nologo/' /boot/firmware/cmdline.txt
    fi

    if ! grep -q "consoleblank=0" /boot/firmware/cmdline.txt; then
        report "disabling console blanking"

        sed_inplace '1 s/$/ consoleblank=0/' /boot/firmware/cmdline.txt
    fi
}
