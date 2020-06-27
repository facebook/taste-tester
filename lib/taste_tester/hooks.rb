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

require 'taste_tester/logging'
require 'between_meals/util'
require 'between_meals/repo/hg'
require 'between_meals/repo/git'

module TasteTester
  # Hooks placeholders
  class Hooks
    extend TasteTester::Logging
    extend BetweenMeals::Util

    # Do stuff before we upload to chef-zero
    def self.pre_upload(_dryrun, _repo, _last_ref, _cur_ref); end

    # Do stuff after we upload to chef-zero
    def self.post_upload(_dryrun, _repo, _last_ref, _cur_ref); end

    # Do stuff before we put hosts in test mode
    def self.pre_test(_dryrun, _repo, _hosts); end

    # This should return an array of commands to execute on
    # remote systems.
    def self.test_remote_cmds(_dryrun, _hostname); end

    # Should return a string with extra stuff to shove
    # in the remote client.rb
    def self.test_remote_client_rb_extra_code(_hostname); end

    # Do stuff after we put hosts in test mode
    def self.post_test(_dryrun, _repo, _hosts); end

    # Additional checks you want to do on the repo
    def self.repo_checks(_dryrun, _repo); end

    # Find the set of roles dependent on the changed files.
    # If returning something other than a set of roles, post_impact and/or
    # print_impact should be specified to handle the output.
    def self.find_impact(_changes); end

    # Do stuff after we find impacted roles
    # This should return a JSON serializable object with the final impact
    # assessment. You will probably also want to define a print_impact method
    # which returns true to override the default output logic.
    def self.post_impact(_impacted_roles); end

    # Customize the printed output of impact
    # If this method returns true, the default output will not be printed.
    def self.print_impact(_final_impact); end

    def self.get(file)
      path = File.expand_path(file)
      logger.warn("Loading plugin at #{path}") unless TasteTester::Config.json
      unless File.exist?(path)
        logger.error('Plugin file not found')
        exit(1)
      end
      class_eval(File.read(path), path, 1)
    end
  end
end
