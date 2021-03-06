#!/bin/bash

#{{begin_exclude}}#
if [[ -n "${_IO_SH_INCLUDED:-}" ]]; then
    return
fi
_IO_SH_INCLUDED=1
#{{end_exclude}}#

# perror prints its arguments to stderr.
perror() {
    printf "%s\n" "$@" >/dev/stderr
    return 0
}

# abort prints its arguments and quits
abort() {
    perror "$@"
    exit 1
}

# report prints annotated stage output to stdout (or if no STAGE_NAME
# is set, just its arguments)
report() {
    if [[ -n "${STAGE_NAME:-}" ]]; then
        printf "  %s: %s\n" "${STAGE_NAME}" "$@"
    else
        printf "%s\n" "$@"
    fi
}

# prompt_default $1=default-value $2...=prompt
#   prompts the user and returns a default value if they provide no
#   reason
prompt_default() {
    local ANSWER
    local DEFAULT="$1"
    shift

    read -er -p "$* [${DEFAULT}]: " ANSWER
    if [ -z "${ANSWER}" ]; then
        ANSWER="${DEFAULT}"
    fi
    echo "${ANSWER}"
}

# prompt $1...=prompt
#   prompts the user and returns their response, which may be empty
prompt() {
    local ANSWER

    read -er -p "$*: " ANSWER
    echo "${ANSWER}"
}

# prompt_pw $1...=prompt
#   prompts the user with terminal echo disabled and returns their
#   response, which may be empty
prompt_pw() {
    local ANSWER

    read -ers -p "$*: " ANSWER
    echo "${ANSWER}"
}
