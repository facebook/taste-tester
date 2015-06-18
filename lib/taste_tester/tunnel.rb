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

module TasteTester
  # Thin ssh tunnel wrapper
  class Tunnel
    include TasteTester::Logging
    include BetweenMeals::Util

    attr_reader :port

    def initialize(host, server, timeout = 5)
      @host = host
      @server = server
      @timeout = timeout
      if TasteTester::Config.testing_until
        @delta_secs = TasteTester::Config.testing_until.strftime('%s').to_i -
                      Time.now.strftime('%s').to_i
      else
        @delta_secs = TasteTester::Config.testing_time
      end
    end

    def run
      @port = TasteTester::Config.tunnel_port
      logger.info("Setting up tunnel on port #{@port}")
      @status, @output = exec!(cmd, logger)
    rescue
      logger.error 'Failed bringing up ssh tunnel'
      exit(1)
    end

    def cmd
      if TasteTester::Config.user != 'root'
        pid = '$$'
      else
        pid = '\\$\\$'
      end
      cmds = "ps -p #{pid} -o pgid | grep -v PGID > #{TasteTester::Config.timestamp_file} &&" +
        " touch -t #{TasteTester::Config.testing_end_time}" +
        " #{TasteTester::Config.timestamp_file} && sleep #{@delta_secs}"
      # As great as it would be to have ExitOnForwardFailure=yes,
      # we had multiple cases of tunnels dying
      # if -f and ExitOnForwardFailure are used together.
      # In most cases the first request from chef was "breaking" the tunnel,
      # in a way that port was still open, but subsequent requests were hanging.
      # This is reproducible and should be looked into.
      cmd = "#{TasteTester::Config.ssh_cmd} " +
        "-T -o BatchMode=yes -o ConnectTimeout=#{@timeout} " +
        '-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ' +
        '-o ServerAliveInterval=10 -o ServerAliveCountMax=6 ' +
        "-f -R #{@port}:localhost:#{@server.port} "
      if TasteTester::Config.user != 'root'
        cc = Base64.encode64(cmds).gsub(/\n/, '')
        cmd += "#{TasteTester::Config.user}@#{@host} \"echo '#{cc}' | base64" +
          ' --decode | sudo bash -x"'
      else
        cmd += "root@#{@host} \"#{cmds}\""
      end
      cmd
    end

    def self.kill(name)
      ssh = TasteTester::SSH.new(name)
      # Since commands are &&'d together, and we're using &&, we need to
      # surround this in paryns, and make sure as a whole it evaluates
      # to true so it doesn't mess up other things... even though this is
      # the only thing we're currently executing in this SSH.
      if TasteTester::Config.user != 'root'
        sudo = 'sudo '
      end
      cmd = "( [ -s #{TasteTester::Config.timestamp_file} ]" +
        " && #{sudo}kill -9 -- -\$(cat #{TasteTester::Config.timestamp_file}); true )"
      ssh << cmd
      ssh.run!
    end
  end
end
