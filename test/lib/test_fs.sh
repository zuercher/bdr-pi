#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_TEST_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/.. && pwd)"
_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/../.. && pwd)"

source "${_TEST_ROOT_DIR}/assertions.sh"
source "${_TEST_ROOT_DIR}/mocks.sh"

source "${_ROOT_DIR}/lib/fs.sh"

BDRPI_TEST_DIR="${TMPDIR:-/tmp/}bdr-pi-test-fs.$$"

before_all() {
    mkdir -p "${BDRPI_TEST_DIR}/a"
    mkdir -p "${BDRPI_TEST_DIR}/b"
}

after_all() {
    rm -rf "${BDRPI_TEST_DIR}"
}

test_push_dir_pop_dir() {
    assert_succeeds push_dir "${BDRPI_TEST_DIR}/a"
    assert_eq "${PWD}" "${BDRPI_TEST_DIR}/a"

    assert_succeeds push_dir "${BDRPI_TEST_DIR}/b"
    assert_eq "${PWD}" "${BDRPI_TEST_DIR}/b"

    assert_succeeds pop_dir
    assert_eq "${PWD}" "${BDRPI_TEST_DIR}/a"

    mock_error abort
    assert_fails push_dir "${BDRPI_TEST_DIR}/c" 2&>1
    expect_mock_called abort
}

test_installed() {
    assert_fails installed "this-could-not-possibly-be-a-binary-on-this-host"

    assert_succeeds installed "ls"
}

source "${_TEST_ROOT_DIR}/test-harness.sh"
