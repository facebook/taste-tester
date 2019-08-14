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

require 'taste_tester/exceptions'

module TasteTester
  # Wrapper for running commands on local system
  class NoOp
    include TasteTester::Logging
    include BetweenMeals::Util

    def initialize
      print_noop_warning
      @host = 'localhost'
      @user = ENV['USER']
      @cmds = []
    end

    def print_noop_warning
      # This needs to be a Class var as this class is initialized more
      # than once in a given tt run and we only want to warn once.
      # rubocop:disable Style/ClassVars
      @@printedwarning ||= logger.warn(
        'No-op plugin active, no remote commands will be run!',
      )
      # rubocop:enable Style/ClassVars
    end

    def add(string)
      @cmds << string
    end

    alias << add

    def run
      run!
    end

    def run!
      cmd
      [0, "# TasteTester by #{@user}"]
    end

    def error!
      # never fails, but interface requires a definition
    end

    private

    def cmd
      @cmds.each do |cmd|
        logger.info("No-op, faking run of: '#{cmd}' on #{@host}")
      end
    end
  end
end
