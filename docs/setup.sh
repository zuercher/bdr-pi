#!/bin/bash

# fail on unset variables
set -u

abort() {
    printf "%s\n" "$@"
    exit 1
}

push_dir() {
    pushd "${1}" >/dev/null || abort "could not change to ${1}"
}

pop_dir() {
    popd || abort "could not pop dir"
}

installed() {
    local BINARY="$1"
    hash "${BINARY}" 2> /dev/null
    return $?
}

# Require bash
# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]; then
    abort "bash is required to interpret this script."
fi

OS="$(uname)"
if [[ "$OS" != "Linux" ]]; then
    abort "OS is ${OS} -- this isn't going to work out."
fi

DISTRIBUTION="$(lsb_release -si)"
if [[ "$DISTRIBUTION" != "Raspbian" ]]; then
    echo "Expected a Raspbian distribution, but we'll muddle on..."
fi

# Check if git is installed.
if ! installed git; then
    # Nope. Tallyho!
    echo "installing git"
    sudo apt-get -y install git
    hash -r

    if ! installed git; then
        abort "tried to install git, but still can't find it on the path"
    fi
fi

REPO="https://github.com/zuercher/bdr-pi"
BDR_DIR="${HOME}/${USER}/.bdr-pi"
if [[ -d "${BDR_DIR}/.git" ]]; then
    # Git repository is present. Let's update it.
    push_dir "${BDR_DIR}"
    git pull || abort "unable to pull $(git remote get-url origin)"
    pop_dir
else
    # No git repository. Clone it.
    git clone "${REPO}" "${BDR_DIR}" || abort "unable to clone ${REPO}"
fi

mkdir -p "${BDR_DIR}/state" || abort "could not create state dir"

# Initial setup is complete, now transfer control to the code in BDR_DIR
export BDR_DIR
sudo "${BDR_DIR}/update.sh" "$@"
