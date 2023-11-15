#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_TEST_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/.. && pwd)"
_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/../.. && pwd)"

source "${_TEST_ROOT_DIR}/assertions.sh"
source "${_TEST_ROOT_DIR}/mocks.sh"

source "${_ROOT_DIR}/lib/io.sh"

after_each() {
    clear_mocks
}

test_perror() {
    assert_stderr_contains "xyz 123" perror "xyz" "123"
}

test_abort() {
    mock_error exit

    assert_stderr_contains "xyz 123" abort "xyz" "123"

    expect_mock_called_with_args exit 1
}

test_report() {
    assert_stdout_contains "xyz 123" report "xyz" "123"

    STAGE_NAME="foo"
    assert_stdout_contains "foo: xyz 123" report "xyz" "123"
    STAGE_NAME=""
}

test_prompt() {
    mock_success_and_set read ANSWER "xyz"

    assert_eq "$(prompt foo bar)" "xyz"
    expect_mock_called_with_args read -er -p "foo bar: " ANSWER
}

test_prompt_default() {
    mock_success_and_set read ANSWER "xyz"

    assert_eq "$(prompt_default default foo bar)" "xyz"
    expect_mock_called_with_args read -er -p "foo bar [default]: " ANSWER
}

test_prompt_default_returns_default() {
    mock_success read

    assert_eq "$(prompt_default default foo bar)" "default"
}

test_prompt_yesno() {
    mock_success_and_set read ANSWER "yEs"
    assert_eq "$(prompt_yesno N foo bar)" "Y"
    expect_mock_called_with_args read -er -p "foo bar [N]: " ANSWER

    clear_mocks
    mock_success_and_set read ANSWER "nos"
    assert_eq "$(prompt_yesno Y foo bar)" "N"

    clear_mocks
    mock_success_and_set read ANSWER "whatever"
    assert_eq "$(prompt_yesno Y foo bar)" "N"

    # test defaults
    clear_mocks
    mock_success read
    assert_eq "$(prompt_yesno N foo bar)" "N"
    expect_mock_called_with_args read -er -p "foo bar [N]: " ANSWER

    clear_mocks
    mock_success read
    assert_eq "$(prompt_yesno Y foo bar)" "Y"
    expect_mock_called_with_args read -er -p "foo bar [Y]: " ANSWER
}

test_prompt_pw() {
    mock_success_and_set read ANSWER "xyz"

    assert_eq "$(prompt_pw foo bar)" "xyz"
    expect_mock_called_with_args read -ers -p "foo bar: " ANSWER
}

test_sed_inplace_darwin() {
    mock_success sed
    mock_success_and_return uname "Darwin"

    assert_succeeds sed_inplace "args"

    expect_mock_called_with_args "sed" "-i" "" "args"
}

test_sed_inplace_linux() {
    mock_success sed
    mock_success_and_return uname "Linux"

    assert_succeeds sed_inplace "args"

    expect_mock_called_with_args "sed" "-i" "args"
}

source "${_TEST_ROOT_DIR}/test-harness.sh"
