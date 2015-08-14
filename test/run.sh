#!/usr/bin/env bash
set -e
set -o verbose
./test/run-git.sh
./test/run-hg.sh
