#!/usr/bin/env bash
set -e
set -o verbose
rm -rf /tmp/ops
HG="hg --config ui.username=foo@bar.com"

function tt {
bundle exec ./bin/taste-tester test -s localhost -y -c ./test/tt-hg.rb -v
}
(
  mkdir /tmp/ops
  cd /tmp/ops
  hg init
  mkdir chef/cookbooks/cookbook1/recipes -p
  touch chef/cookbooks/cookbook1/recipes/default.rb
  echo "name 'cookbook1'" > chef/cookbooks/cookbook1/metadata.rb
  $HG add .
  $HG commit -m "Add cookbook1"
)
tt
