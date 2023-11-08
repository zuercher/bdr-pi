#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_TEST_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/.. && pwd)"
_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/../.. && pwd)"

source "${_TEST_ROOT_DIR}/assertions.sh"

source "${_ROOT_DIR}/lib/setup_config.sh"

export BDRPI_SETUP_CONFIG_FILE="${TMPDIR:-/tmp/}/bdrpi-test-setup-config.$$.txt"

after_each() {

    rm -f "${BDRPI_SETUP_CONFIG_FILE}"
    reset_setup_config
}

_append() {
    echo "$@" >>"${BDRPI_SETUP_CONFIG_FILE}"
}

test_load_config() {
    # missing config ok
    _load_config || assert_failed "failed to load missing config"

    # empty config ok
    touch "${BDRPI_SETUP_CONFIG_FILE}"
    _load_config || assert_failed "failed to load empty config"

    # loads a key
    _append "FOO=BAR"
    _load_config || assert_failed "failed to load config"
    assert_eq "$(get_setup_config "FOO")" "BAR"
}

test_load_config_once() {
    # set up some config
    _append "FOO=BAR"
    _load_config_once || assert_failed "failed to load config once"
    assert_eq "$(get_setup_config "FOO")" "BAR"

    # add more
    _append "QUX=BAZ"
    _load_config_once || assert_failed "failed to load config once (reload)"

    # verify previous key is still set
    assert_eq "$(get_setup_config "FOO")" "BAR"

    # verify new key was not loaded
    assert_eq "$(get_setup_config "QUX")" ""
}

test_set_setup_config() {
    set_setup_config "FOO" "BAR" || assert_failed "error setting key"
    assert_eq "$(get_setup_config "FOO")" "BAR"

    # Test loading from scratch
    reset_setup_config
    assert_eq "$(get_setup_config "FOO")" "BAR"
}

test_set_setup_config_replace() {
    set_setup_config "FOO" "BAR" || assert_failed "error setting key"
    assert_eq "$(get_setup_config "FOO")" "BAR"

    reset_setup_config

    set_setup_config "FOO" "QUX" || assert_failed "error setting key"

    assert_eq "$(get_setup_config "FOO")" "QUX"
    reset_setup_config
    assert_eq "$(get_setup_config "FOO")" "QUX"
}

test_set_setup_config_array() {
    set_setup_config_array "ARRAY" "append" "first" || assert_failed "error setting ARRAY[0]=first"
    set_setup_config_array "ARRAY" "append" "second" || assert_failed "error setting ARRAY[1]=second"
    set_setup_config_array "ARRAY" "append" "third" || assert_failed "error setting ARRAY[2]=third"

    assert_eq "$(get_setup_config_array_size ARRAY)" "3"

    assert_eq "$(get_setup_config_array "ARRAY" "0")" "first"
    assert_eq "$(get_setup_config_array "ARRAY" "1")" "second"
    assert_eq "$(get_setup_config_array "ARRAY" "2")" "third"

    reset_setup_config

    assert_eq "$(get_setup_config_array "ARRAY" "0")" "first"
    assert_eq "$(get_setup_config_array "ARRAY" "1")" "second"
    assert_eq "$(get_setup_config_array "ARRAY" "2")" "third"

    set_setup_config_array "ARRAY" "append" "fourth" || assert_failed "error setting ARRAY[3]=fourth"
    assert_eq "$(get_setup_config_array "ARRAY" "3")" "fourth"
}

test_set_setup_config_array_replace() {
    set_setup_config_array "ARRAY" "append" "first" || assert_failed "error setting ARRAY[0]=first"
    set_setup_config_array "ARRAY" "append" "second" || assert_failed "error setting ARRAY[1]=second"
    set_setup_config_array "ARRAY" "append" "third" || assert_failed "error setting ARRAY[2]=third"

    set_setup_config_array "ARRAY" "1" "MOAR SECOND"  || assert_failed "error setting ARRAY[1]=MOAR SECOND"

    assert_eq "$(get_setup_config_array "ARRAY" "0")" "first"
    assert_eq "$(get_setup_config_array "ARRAY" "1")" "MOAR SECOND"
    assert_eq "$(get_setup_config_array "ARRAY" "2")" "third"
}

test_set_setup_config_array_clear() {
    set_setup_config_array "ARRAY" "append" "first" || assert_failed "error setting ARRAY[0]=first"
    set_setup_config_array "ARRAY" "append" "second" || assert_failed "error setting ARRAY[1]=second"
    set_setup_config_array "ARRAY" "append" "third" || assert_failed "error setting ARRAY[2]=third"

    assert_eq "$(get_setup_config_array "ARRAY" "0")" "first"
    assert_eq "$(get_setup_config_array "ARRAY" "1")" "second"
    assert_eq "$(get_setup_config_array "ARRAY" "2")" "third"

    clear_setup_config_array "ARRAY"

    assert_eq "$(get_setup_config_array_size ARRAY)" "0"

    reset_setup_config

    assert_eq "$(get_setup_config_array_size ARRAY)" "0"
}

source "${_TEST_ROOT_DIR}/test-harness.sh"
