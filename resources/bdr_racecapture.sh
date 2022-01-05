#!/bin/bash

# abort prints its arguments and quits
abort() {
    printf "%s\n" "$@" >/dev/stderr
    exit 1
}

DIR="{{SETUP_HOME}}"
[[ "${DIR}" == "$(realpath "${DIR}")" ]] || abort "${DIR} must be absolute"
[[ -d "${DIR}" ]] || abort "no such directory: ${DIR}"

RC_DIR="${DIR}/racecapture"
[[ -d "${RC_DIR}" ]] || abort "no such directory: ${RC_DIR}"

LOG_DIR="${DIR}/logs"
KIVY_DIR="${DIR}/.kivy"

# Configure keyring to store Podium user credentials
export PYTHON_KEYRING_BACKEND=sagecipher.keyring.Keyring
killall ssh-agent &>/dev/null
eval "$(ssh-agent -s)" &>/dev/null
ssh-add &>/dev/null

KEEP_N_LOGS=$((10))
MIN_RUNTIME=$((5))
SHORT_RUNTIME=$((0))

cd "${RC_DIR}" ||:
while true; do
    # Delete all but the last KEEP_N_LOGS logs
    find "${LOG_DIR}" -name "*.log" -print | sort -r | tail -n +$((KEEP_N_LOGS+1)) | xargs rm -f

    LOGFILE="${LOG_DIR}/racecapture_$(date "+%Y%m%d_%H%M%S").log"

    START="$(date "+%s")"
    ./race_capture >> "${LOGFILE}" 2>&1
    echo "exit code $?"
    END="$(date +"%s")"

    RUNTIME=$((END-START))
    if [[ "${RUNTIME}" -lt "${MIN_RUNTIME}" ]]; then
        echo "racecapture quit after ${RUNTIME} seconds" >> "${LOGFILE}"

        SHORT_RUNTIME=$((SHORT_RUNTIME+1))
        if [[ "${SHORT_RUNTIME}" -ge $((KEEP_N_LOGS/2)) ]]; then
            abort "too many consecutive early exits, giving up"
        fi
    else
        SHORT_RUNTIME=$((0))
    fi
done
