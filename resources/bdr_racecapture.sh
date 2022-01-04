#!/bin/bash

# abort prints its arguments and quits
abort() {
    printf "%s\n" "$@" >/dev/stderr
    exit 1
}

DIR="{{SETUP_HOME}}"

cd "${DIR}" || abort "cd to ${DIR} failed"

LOG_DIR="${DIR}/logs"
mkdir -p "${LOG_DIR}"

KEEP_N_LOGS=$((10))
MIN_RUNTIME=$((5))
SHORT_RUNTIME=$((0))
while true; do
    # Delete all but the last KEEP_N_LOGS logs
    find "${LOG_DIR}" -name "*.log" -print | sort -r | tail -n +$((KEEP_N_LOGS+1)) | xargs rm -f

    LOGFILE="${LOG_DIR}/racecapture_$(date "+%Y%m%d_%H%M%S").log"

    START="$(date "+%s")"
    "${DIR}"/racecapture/run_racecapture.sh -l "${LOGFILE}"
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
