#!/bin/bash

usage() {
    echo "usage: $0 <input> <output>"
    exit 1
}

DIR="$(cd "$(dirname "$0")/.." && pwd)"

INPUT="$1"
OUTPUT="$2"

[[ -z "${INPUT}" ]] && usage
[[ -z "${OUTPUT}" ]] && usage

TEMP_DIR="$(mktemp -d -t bdr-pi-apply-tmpl)"

SCRIPT="${TEMP_DIR}/apply-templates.sed"
find "${DIR}/lib" -type f -a -name "*.sh" -print \
    | while read -r FILE; do
    FILE_BASE="$(basename "${FILE}")"
    TMPL_FILE="${TEMP_DIR}/${FILE_BASE}"

    if ! sed -e '/#!/,/^$/d; /#{{begin_exclude}}#/,/#{{end_exclude}}#/d' "${FILE}" >"${TMPL_FILE}"; then
        echo "error preparing ${FILE}"
        exit 1
    fi

    cat >>"${SCRIPT}" << EOF
      /#{{include ${FILE_BASE}}}#/{
        r ${TMPL_FILE}
        d
      }
EOF
done

if ! sed -f "${SCRIPT}" "${INPUT}" >"${OUTPUT}"; then
    echo "error applying templates"
    exit 1
fi

rm -rf "${TEMP_DIR}"
