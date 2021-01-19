#!/usr/bin/env bash

# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

# Copyright 2013-present Facebook
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
set -o verbose
bundle exec chef-zero &
ZERO=$!
trap "kill -9 $ZERO" EXIT
SOURCE=/tmp/ops
sleep 5
GIT="git -c user.email='foo@bar.com' -c user.name='foobar'"

function tt {
  bundle exec ./bin/taste-tester test -ys localhost -c $1 -vv
}
(
  mkdir $SOURCE
  git init $SOURCE
  cd $SOURCE
  mkdir chef/cookbooks/cookbook1/recipes -p
  touch chef/cookbooks/cookbook1/recipes/default.rb
  echo "name 'cookbook1'" > chef/cookbooks/cookbook1/metadata.rb
  $GIT add . -A
  $GIT commit -m "Add cookbook1"
)
tt ./test/tt-git.rb
tt ./test/tt-auto.rb
