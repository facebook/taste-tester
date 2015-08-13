#!/usr/bin/env bash
set -e
set -o verbose
rm -rf /tmp/ops
GIT="git -c user.email='foo@bar.com' -c user.name='foobar'"

function tt {
bundle exec ./bin/taste-tester test -s localhost -y -c ./test/tt-git.rb -v
}
(
  git init /tmp/ops
  cd /tmp/ops
  mkdir chef/cookbooks/cookbook1/recipes -p
  touch chef/cookbooks/cookbook1/recipes/default.rb
  echo "name 'cookbook1'" > chef/cookbooks/cookbook1/metadata.rb
  $GIT add . -A
  $GIT commit -m "Add cookbook1"
)
tt
