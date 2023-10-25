#!/bin/bash

run_stage() {
    local RC_URL="$(curl -s https://podium.live/software | \
                         grep -Po '(?<=<a href=")[^"]*racecapture_linux_raspberrypi[^"]*.bz2[^"]*' | \
                         python3 -c 'import html, sys; [print(html.unescape(l), end="") for l in sys.stdin]')"
    local RC_FILE="$(basename "${RC_URL}" | sed 's/\?.*//')"

    push_dir "/opt"

    rm -f "${RC_FILE}"

    # download and extract as the setup user to keep the permissions correct
    report "downloading ${RC_URL}"
    sudo -u "${SETUP_USER}" wget -O "${RC_FILE}" --no-verbose "${RC_URL}" || \
        abort "unable to download ${RC_URL}"

    report "extracting ${RC_FILE}"
    sudo -u "${SETUP_USER}" tar xfj "${RC_FILE}" || abort "unable to extract ${RC_FILE}"

    [[ -d "/opt/racecapture" ]] || abort "missing /opt/racecapture directory"

    pop_dir
}
