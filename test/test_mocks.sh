#!/bin/bash

_TEST_SH="${BASH_SOURCE[0]}"
_TEST_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")" && pwd)"
_ROOT_DIR="$(cd "$(dirname "${_TEST_SH}")"/.. && pwd)"

source "${_TEST_ROOT_DIR}/mocks.sh"
source "${_TEST_ROOT_DIR}/assertions.sh"

example_function() {
    assert_failed "example_function should never be called"
}

after_each() {
    clear_mocks
}

test_mock_success() {
    mock_success example_function

    example_function

    expect_mock_called example_function
}

source "${_TEST_ROOT_DIR}/test-harness.sh"
