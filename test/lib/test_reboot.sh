#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_TEST_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/.. && pwd)"
_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/../.. && pwd)"

source "${_TEST_ROOT_DIR}/assertions.sh"
source "${_TEST_ROOT_DIR}/mocks.sh"

source "${_ROOT_DIR}/lib/reboot.sh"

export SETUP_HOME="${TMPDIR:-/tmp/}bdr-pi-test-reboot.$$"
export SETUP_USER="bob"

before_all() {
    mkdir -p "${SETUP_HOME}"
}

before_each() {
    touch "${SETUP_HOME}/.bashrc"
}

after_each() {
    rm -f "${SETUP_HOME}/.bashrc"
    clear_mocks
}

after_all() {
    rm -rf "${SETUP_HOME}"
}

test_reboot_configure() {
    assert_fails reboot_configured

    echo "# BEGIN_ON_REBOOT STUFF" >"${SETUP_HOME}/.bashrc"
    assert_succeeds reboot_configured
}

test_reboot_clear() {
    cat >"${SETUP_HOME}/.bashrc" <<EOF
before
# BEGIN_ON_REBOOT STUFF
  reboot stuff"
# END_ON_REBOOT STUFF
after
EOF

    assert_succeeds reboot_clear

    assert_succeeds grep -q before "${SETUP_HOME}/.bashrc"
    assert_succeeds grep -q after "${SETUP_HOME}/.bashrc"
    assert_fails grep -q "reboot stuff" "${SETUP_HOME}/.bashrc"
}

test_reboot_clear_no_bashrc() {
    rm -f "${SETUP_HOME}/.bashrc"

    mock_error abort
    assert_fails reboot_clear
}

test_reboot_required() {
    cat >"${SETUP_HOME}/.bashrc" <<EOF
before
EOF

    mock_success report
    export SETUP_TTY="/dev/tty0"

    assert_succeeds reboot_required
    assert_succeeds reboot_is_required
    assert_succeeds reboot_configured

    assert_succeeds grep -q "# BEGIN_ON_REBOOT VIA terminal" "${SETUP_HOME}/.bashrc"
}

test_reboot_required_no_bashrc() {
    rm -f "${SETUP_HOME}/.bashrc"

    mock_error abort
    assert_fails reboot_required
}

test_reboot_required_pseudo_tty() {
    cat >"${SETUP_HOME}/.bashrc" <<EOF
before
EOF

    mock_success report
    export SETUP_TTY="/dev/pts/1"

    assert_succeeds reboot_required
    assert_succeeds reboot_is_required
    assert_succeeds reboot_configured

    assert_succeeds grep -q "# BEGIN_ON_REBOOT VIA pseudo-terminal" "${SETUP_HOME}/.bashrc"
}

test_reboot_required_repeat_same_tty() {
    cat >"${SETUP_HOME}/.bashrc" <<EOF
before
EOF

    mock_success report
    export SETUP_TTY="/dev/tty0"

    assert_succeeds reboot_required
    assert_succeeds reboot_configured

    assert_succeeds reboot_required
    expect_mock_called_with_args report "reboot already scheduled"
}

test_reboot_required_repeat_different_tty() {
    cat >"${SETUP_HOME}/.bashrc" <<EOF
before
EOF

    mock_success report
    export SETUP_TTY="/dev/tty0"

    assert_succeeds reboot_required
    assert_succeeds reboot_configured

    assert_fails grep -q "# BEGIN_ON_REBOOT VIA pseudo-terminal" "${SETUP_HOME}/.bashrc"

    export SETUP_TTY="/dev/pts/1"
    assert_succeeds reboot_required
    assert_succeeds reboot_configured

    assert_succeeds grep -q "# BEGIN_ON_REBOOT VIA pseudo-terminal" "${SETUP_HOME}/.bashrc"
}

source "${_TEST_ROOT_DIR}/test-harness.sh"
