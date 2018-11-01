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
rm -rf /tmp/ops
HG="hg --config ui.username=foo@bar.com"

function tt {
  bundle exec ./bin/taste-tester test -s localhost -y -c $1 -v
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
tt ./test/tt-hg.rb
tt ./test/tt-auto.rb
