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

    def initialize(host, server)
      @host = host
      @server = server
    end

    def run
      @port = TasteTester::Config.tunnel_port
      logger.info("Setting up tunnel on port #{@port}")
      exec!(cmd, logger)
    rescue StandardError => e
      logger.error "Failed bringing up ssh tunnel: #{e}"
      exit(1)
    end

    def cmd
      @ts = TasteTester::Config.testing_end_time.strftime('%y%m%d%H%M.%S')

      # Tie the life of our SSH tunnel with the life of timestamp file.
      # taste-testing can be renewed, so we'll wait until:
      # 1. the timestamp file is entirely gone
      # 2. our parent sshd process dies
      # 3. new taste-tester instance is running (file contains different PGID)
      cmds = <<~EOS
      log() {
        [ -e /usr/bin/logger ] || return
        logger -t taste-tester "$*"
      }
      # sets $current_pgid
      # This is important, this should just be called ald let it set the
      # variable. Do NOT call in a subshell like foo=$(get_current_pgid)
      # as then you end up even further down the list of children
      get_current_pgid() {

        # if TT user is non-root, then it breaks down like this:
        #   we are 'bash'
        #   our parent is 'sudo'
        #   our parent's parent is 'bash "echo ..." | sudo bash -x'
        #   our parent's parent's parent is ssh
        #   - we want the progress-group ID of *that*
        #
        # EXCEPT... sometimes sudo forks itself one more time so it's
        #   we are 'bash'
        #   our parent is 'sudo'
        #   our parent's parent 'sudo'
        #   our parent's parent's parent is 'bash "echo ..." | sudo bash -x'
        #   our parent's parent's parent's parent is ssh
        #   - we want the progress-group ID of *that*
        #
        # BUT if the TT user is root, no sudo at all...
        #   we are 'bash'
        #   our parent is 'bash "echo ..." | bash -c
        #   our parent's parent is ssh
        #   - we want the progress-group ID of *that*
        #
        # We can make all sorts of assumptions, but the most reliable way
        # to do this that's always correct is to is simply to walk parents until
        # we hit something with SSH in the name. Start with PPID and go from
        # there.
        #
        # There's a few commented out 'log's here that are too verbose
        # for operation (since this function runs every minute)  but are useful
        # for debugging.

        relevant_pid=''
        current_pid=$PPID
        while true; do
          name=$(ps -o command= -p $current_pid)
          if [[ "$name" =~ sshd ]]; then
            # Uncomment the following for debugging...
            #log "$current_pid is ssh, that's us!"
            relevant_pid=$current_pid
            break
          fi
          # Uncomment the following for debugging...
          #log "$current_pid is $name, finding parent..."
          current_pid=$(ps -o ppid= -p $current_pid)
        done
        if [ -z "$relevant_pid" ];then
          log "Cannot determine relevant PGID"
          exit 42
        fi
        current_pgid="$(ps -o pgid= -p $relevant_pid | sed "s| ||g")"
        # Uncomment the following for debugging...
        #log "PGID of ssh ($relevant_pid) is $current_pgid"
      }
      get_current_pgid
      SSH_PGID=$current_pgid

      echo $SSH_PGID > #{TasteTester::Config.timestamp_file} && \
      touch -t #{@ts} #{TasteTester::Config.timestamp_file} && \
      while true; do
        if ! [ -f "#{TasteTester::Config.timestamp_file}" ]; then
          log "Ending tunnel: timestamp file disappeared"
          break
        fi
        current_pid="$(cat #{TasteTester::Config.timestamp_file})"
        if ! [ "$current_pid" = "$SSH_PGID" ]; then
          log "Ending tunnel: timestamp PGID changed"
          break
        fi
        get_current_pgid
        if ! [ "$current_pgid" = "$SSH_PGID" ]; then
          log "Ending tunnel: timestamp PGID isn't ours"
          break
        fi
        sleep 60
      done
      EOS
      # As great as it would be to have ExitOnForwardFailure=yes,
      # we had multiple cases of tunnels dying
      # if -f and ExitOnForwardFailure are used together.
      # In most cases the first request from chef was "breaking" the tunnel,
      # in a way that port was still open, but subsequent requests were hanging.
      # This is reproducible and should be looked into.
      jumps = TasteTester::Config.jumps ? "-J #{TasteTester::Config.jumps}" : ''
      cmd = "#{TasteTester::Config.ssh_command} #{jumps} " +
            "-o ConnectTimeout=#{TasteTester::Config.ssh_connect_timeout} " +
            '-T -o BatchMode=yes ' +
            '-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ' +
            '-o ServerAliveInterval=10 -o ServerAliveCountMax=6 ' +
            "-f -R #{@port}:localhost:#{@server.port} "
      cc = Base64.encode64(cmds).delete("\n")

      # always base64 encode the command so we don't have to deal with quoting
      cmd += "#{TasteTester::Config.user}@#{@host} \"echo '#{cc}' | base64" +
             ' --decode'
      if TasteTester::Config.user != 'root'
        cmd += ' | sudo bash -x"'
      else
        cmd += ' | bash -x"'
      end
      cmd
    end

    def self.kill(name)
      ssh = TasteTester::SSH.new(name)
      # Since commands are &&'d together, and we're using &&, we need to
      # surround this in paryns, and make sure as a whole it evaluates
      # to true so it doesn't mess up other things... even though this is
      # the only thing we're currently executing in this SSH.
      cmd = "( [ -s #{TasteTester::Config.timestamp_file} ]" +
            ' && kill -9 -- ' +
            "-\$(cat #{TasteTester::Config.timestamp_file}) 2>/dev/null; " +
            ' true )'
      ssh << cmd
      ssh.run!
    end
  end
end
