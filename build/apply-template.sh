#!/bin/bash

#/# Scans the input for comments of the form:
#/#   #{{include file.sh}}#
#/# and substitutes the contents of lib/file.sh into the input and
#/# writes the modified file as the output. If lib/file.sh contains
#/# lines book-ended with:
#/#   #{{begin_exclude}}#
#/#   #{{end_exclude}}#
#/# those lines are not copied into the output.
usage() {
    echo "usage: $0 <input> <output>"
    echo
    grep -E "^#/#" "$0" | cut -c 5-
    exit 1
}

DIR="$(cd "$(dirname "$0")/.." && pwd)"

case "$1" in
    -h|-help|--help)
        usage
        ;;
    *)
        INPUT="$1"
        ;;
esac
OUTPUT="$2"

[[ -z "${INPUT}" ]] && usage
[[ -z "${OUTPUT}" ]] && usage

TEMP_DIR="$(mktemp -d -t bdr-pi-apply-tmpl)"

# Write sed code to a script: need new lines to allow r and d commands
# in a single block.
SCRIPT="${TEMP_DIR}/apply-templates.sed"

# For each script in lib, strip the code in begin_exclude/end_exclude,
# write the modified file to TEMP_DIR, and add a statement to the sed
# script to substitute it.
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

# Run the generated script against INPUT, writing to OUTPUT.
if ! sed -f "${SCRIPT}" "${INPUT}" >"${OUTPUT}"; then
    echo "error applying templates"
    exit 1
fi

rm -rf "${TEMP_DIR}"
