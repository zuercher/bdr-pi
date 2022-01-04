#!/bin/bash

run_stage() {
    local GPU_MEM="${BDRPI_GPU_MEM:-256}"

    boot_config_set "all" "gpu_mem" "${GPU_MEM}"
}
