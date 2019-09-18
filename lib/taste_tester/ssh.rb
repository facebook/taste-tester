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
  # Thin ssh wrapper
  class SSH
    include TasteTester::Logging
    include BetweenMeals::Util

    def initialize(host, tunnel = false)
      @host = host
      @tunnel = tunnel
      @cmds = []
    end

    def add(string)
      @cmds << string
    end

    alias << add

    def run
      exec(cmd, logger)
    end

    def run!
      exec!(cmd, logger)
    rescue StandardError => e
      logger.error(e.message)
      error!
    end

    def error!
      error = <<-ERRORMESSAGE
SSH returned error while connecting to #{TasteTester::Config.user}@#{@host}
The host might be broken or your SSH access is not working properly
Try doing
  #{TasteTester::Config.ssh_command} -v #{TasteTester::Config.user}@#{@host}
to see if ssh connection is good.
If ssh works, add '-v' key to taste-tester to see the list of commands it's
trying to execute, and try to run them manually on destination host
      ERRORMESSAGE
      error.lines.each { |x| logger.error x.strip }
      fail TasteTester::Exceptions::SshError
    end

    private

    def cmd
      @cmds.each do |cmd|
        logger.info("Will run: '#{cmd}' on #{@host}")
      end
      cmds = @cmds.join(' && ')
      cmd = "#{TasteTester::Config.ssh_command} " +
            '-T -o BatchMode=yes ' +
            "-o ConnectTimeout=#{TasteTester::Config.ssh_connect_timeout} " +
            "#{TasteTester::Config.user}@#{@host} "
      if TasteTester::Config.user != 'root'
        cc = Base64.encode64(cmds).delete("\n")
        cmd += "\"echo '#{cc}' | base64 --decode | sudo bash -x\""
      else
        cmd += "\'#{cmds}\'"
      end
      cmd
    end
  end
end
