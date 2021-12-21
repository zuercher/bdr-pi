#!/bin/bash

export BDR_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"${BDR_DIR}/update.sh" --test "$@"
