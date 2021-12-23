#!/bin/bash

#{{begin_exclude}}#
if [[ -n "${_FS_SH_INCLUDED}" ]]; then
    return
fi
_FS_SH_INCLUDED=1
_FS_SH="${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}"
_FS_LIB_DIR="$(cd "$(dirname "${_FS_SH}")" )"
source "${_FS_LIB_DIR}/io.sh"
#{{end_exclude}}#

# push_dir <dir> invokes pushd and aborts the script on error.
push_dir() {
    pushd "${1}" >/dev/null || abort "could not change to ${1}"
}

# pop_dir invokes popd and aborts the script on error.
pop_dir() {
    popd >/dev/null || abort "could not pop dir"
}

# installed <app> returns success if the given app is on the PATH.
installed() {
    local BINARY="$1"
    hash "${BINARY}" 2> /dev/null
    return $?
}
