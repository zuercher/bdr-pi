#!/bin/bash

run_stage() {
    report "updating apt repo and upgrading installed packages"

    apt-get update || abort "unable to update apt repositories"

    apt-get upgrade -y || abort "unable to update installed packages"
}
