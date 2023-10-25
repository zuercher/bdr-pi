#!/bin/bash

run_stage() {
    # Disable pi logo, console blanking, and the splash screen
    if ! grep -q "logo\.nologo" /boot/cmdline.txt; then
        sed -i '1 s/$/ logo.nologo/' /boot/cmdline.txt
    fi
    if ! grep -q "consoleblank=0" /boot/cmdline.txt; then
        sed -i '1 s/$/ consoleblank=0/' /boot/cmdline.txt
    fi

    # Disable splash screen
    if ! grep -q "^disable_splash" /boot/config.txt; then
        echo "disable_splash=1" >> /boot/config.txt
    fi
}
