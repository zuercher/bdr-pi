#!/bin/bash

run_stage() {
    report "updating apt repo and upgrading installed packages"

    apt-get update -q -y || abort "unable to update apt repositories"

    apt-get upgrade -q -y || abort "unable to update installed packages"
}
