#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_TEST_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/.. && pwd)"
_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/../.. && pwd)"

source "${_TEST_ROOT_DIR}/assertions.sh"
source "${_TEST_ROOT_DIR}/mocks.sh"

source "${_ROOT_DIR}/lib/boot_config.sh"

export BDRPI_BOOT_CONFIG_TXT="${TMPDIR:-/tmp/}/bdrpi-test-boot-config.$$.txt"

before_each() {
    mock_success reboot_required
}

after_each() {
    clear_mocks
    rm -f "${BDRPI_BOOT_CONFIG_TXT}"
}

test_boot_config_contains_regex() {
    # create example /boot/config.txt
    cat >"${BDRPI_BOOT_CONFIG_TXT}" <<EOF
default_all_key=0

[foo]
the_foo_key=1

the_bar_key=2

[all]
an_all_key=3

[foo]
another_foo_key=3

EOF

    assert_succeeds boot_config_contains_regex 'foo' 'the_foo_key'
    assert_succeeds boot_config_contains_regex 'foo' 'another_foo_key'
    assert_succeeds boot_config_contains_regex 'foo' 'the_.+_key'

    assert_succeeds boot_config_contains_regex 'all' 'an_all_key'
    assert_succeeds boot_config_contains_regex 'all' 'default_all_key'
    assert_succeeds boot_config_contains_regex 'all' '.+_all_key'

    assert_fails boot_config_contains_regex 'all' 'no_such_key'
    assert_fails boot_config_contains_regex 'foo' 'no_such_key'
}

test_boot_config_contains() {
    # create example /boot/config.txt
    cat >"${BDRPI_BOOT_CONFIG_TXT}" <<EOF
default_all_key=0

[foo]
the_foo_key=1

the_bar_key=2

[all]
an_all_key=3

[foo]
another_foo_key=4

EOF

    assert_succeeds boot_config_contains 'foo' 'the_foo_key' '1'
    assert_succeeds boot_config_contains 'foo' 'another_foo_key' '4'

    assert_succeeds boot_config_contains 'all' 'an_all_key' '3'
    assert_succeeds boot_config_contains 'all' 'default_all_key' '0'

    assert_fails boot_config_contains 'foo' 'no_such_key' 'x'
    assert_fails boot_config_contains 'foo' 'the_foo_key' 'x'
    assert_fails boot_config_contains 'foo' 'all_all_key' '0'

    assert_fails boot_config_contains 'all' 'no_such_key' 'x'
    assert_fails boot_config_contains 'all' 'an_all_key' 'x'
    assert_fails boot_config_contains 'all' 'the_foo_key' '1'
}

test_boot_config_printf() {
    touch "${BDRPI_BOOT_CONFIG_TXT}"

    assert_fails boot_config_contains 'all' 'first_key' '1'
    assert_succeeds boot_config_printf 'all' '%s=%s\n' 'first_key' '1'
    assert_succeeds boot_config_contains 'all' 'first_key' '1'

    assert_fails boot_config_contains 'foo' 'second_key' '2'
    assert_succeeds boot_config_printf 'foo' '%s=%s\n' 'second_key' '2'
    assert_succeeds boot_config_contains 'foo' 'second_key' '2'

    expect_mock_called reboot_required
}

test_boot_config_replace() {
    touch "${BDRPI_BOOT_CONFIG_TXT}"

    assert_succeeds boot_config_printf 'all' '%s=%s\n' 'first_key' '1'
    assert_succeeds boot_config_printf 'foo' '%s=%s\n' 'second_key' '2'
    assert_succeeds boot_config_printf 'all' '%s=%s\n' 'third_key' '3'

    assert_succeeds boot_config_contains 'all' 'first_key' '1'
    assert_succeeds boot_config_contains 'all' 'third_key' '3'
    assert_succeeds boot_config_contains 'foo' 'second_key' '2'
    clear_mock_calls

    assert_succeeds boot_config_replace 'all' 'first_key' '11'
    assert_succeeds boot_config_contains 'all' 'first_key' '11'
    expect_mock_called reboot_required
    clear_mock_calls

    assert_succeeds boot_config_replace 'foo' 'second_key' 'two'
    assert_succeeds boot_config_contains 'foo' 'second_key' 'two'
    expect_mock_called reboot_required
    clear_mock_calls

    mock_error abort
    assert_fails boot_config_replace 'no-such-section' 'a' 'b'
    assert_fails boot_config_replace 'all' 'no-such-key' 'b'

    expect_mock_not_called reboot_required
    assert_fails boot_config_contains 'no-such-section' 'a' 'b'
    assert_fails boot_config_contains 'all' 'no-such-key' 'b'
}

test_boot_config_set() {
    # create example /boot/config.txt
    cat >"${BDRPI_BOOT_CONFIG_TXT}" <<EOF
default_all_key=0

[foo]
the_foo_key=1
#the_bar_key=2

[all]
an_all_key=3

[foo]
another_foo_key=4
EOF

    assert_succeeds boot_config_contains 'foo' 'the_foo_key' '1'
    assert_fails boot_config_contains 'foo' 'the_bar_key' '2'
    assert_succeeds boot_config_contains 'foo' 'another_foo_key' '4'
    assert_succeeds boot_config_contains 'all' 'default_all_key' '0'
    assert_succeeds boot_config_contains 'all' 'an_all_key' '3'

    mock_error abort

    assert_succeeds boot_config_set 'all' 'default_all_key' 'zero'
    assert_succeeds boot_config_set 'all' 'an_all_key' 'three'
    assert_succeeds boot_config_set 'foo' 'the_foo_key' 'one'
    assert_succeeds boot_config_set 'foo' 'the_bar_key' 'two'
    assert_succeeds boot_config_set 'foo' 'another_foo_key' 'four'
    assert_succeeds boot_config_set 'all' 'last_all_key' 'five'
    assert_succeeds boot_config_set 'foo' 'last_foo_key' 'six'

    expect_mock_not_called abort

    assert_succeeds boot_config_contains 'foo' 'the_foo_key' 'one'
    assert_succeeds boot_config_contains 'foo' 'the_bar_key' 'two'
    assert_succeeds boot_config_contains 'foo' 'another_foo_key' 'four'
    assert_succeeds boot_config_contains 'foo' 'last_foo_key' 'six'
    assert_succeeds boot_config_contains 'all' 'default_all_key' 'zero'
    assert_succeeds boot_config_contains 'all' 'an_all_key' 'three'
    assert_succeeds boot_config_contains 'all' 'last_all_key' 'five'
}

source "${_TEST_ROOT_DIR}/test-harness.sh"
