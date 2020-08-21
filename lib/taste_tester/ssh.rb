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
require 'taste_tester/ssh_util'

module TasteTester
  # Thin ssh wrapper
  class SSH
    include TasteTester::Logging
    include BetweenMeals::Util
    include TasteTester::SSH::Util

    def initialize(host, tunnel = false)
      @host = host
      @tunnel = tunnel
      @cmds = []
    end

    def add(string)
      @cmds << string
    end

    alias << add

    def run(stream = nil)
      exec(cmd, logger, stream)
    end

    def run!(stream = nil)
      exec!(cmd, logger, stream)
    rescue StandardError => e
      logger.error(e.message)
      error!
    end

    private

    def cmd
      @cmds.each do |cmd|
        logger.info("Will run: '#{cmd}' on #{@host}")
      end
      build_ssh_cmd(ssh_base_cmd, @cmds)
    end
  end
end
