#!/bin/bash

set +e

# TODO: any user config (auto-login, etc)
# TODO: modify /home/pi/.bashrc to auto run setup

# disable running this script on boot
sed -i '' 's/ systemd.run.*//g' /boot/cmdline.txt

# clean ourselves up
rm -f /boot/firstrun.sh

exit 0
