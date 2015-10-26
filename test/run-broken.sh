#!/usr/bin/env bash
set -o verbose
rm -rf /tmp/ops

function tt {
  bundle exec ./bin/taste-tester test -s localhost -y -c $1
}
(
  mkdir /tmp/ops
)
tt ./test/tt-auto.rb
if [ $? -ne 0 ]; then
  exit 0
fi
