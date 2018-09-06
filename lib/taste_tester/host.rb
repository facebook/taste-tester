# frozen_string_literal: true

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

require 'fileutils'
require 'base64'
require 'open3'
require 'colorize'

require 'taste_tester/ssh'
require 'taste_tester/noop'
require 'taste_tester/locallink'
require 'taste_tester/tunnel'
require 'taste_tester/exceptions'

module TasteTester
  # Manage state of the remote node
  class Host
    include TasteTester::Logging

    TASTE_TESTER_CONFIG = 'client-taste-tester.rb'
    USER_PREAMBLE = '# TasteTester by '

    attr_reader :name

    def initialize(name, server)
      @name = name
      @user = ENV['USER']
      @server = server
      if TasteTester::Config.use_ssh_tunnels
        @tunnel = TasteTester::Tunnel.new(@name, @server)
      end
    end

    def runchef
      logger.warn("Running '#{TasteTester::Config.chef_client_command}' " +
                  "on #{@name}")
      cmd = "#{TasteTester::Config.ssh_command} " +
            "#{TasteTester::Config.user}@#{@name} "
      if TasteTester::Config.user != 'root'
        cc = Base64.encode64(cmds).delete("\n")
        cmd += "\"echo '#{cc}' | base64 --decode | sudo bash -x\""
      else
        cmd += "\"#{cmds}\""
      end
      status = IO.popen(
        cmd,
      ) do |io|
        # rubocop:disable AssignmentInCondition
        while line = io.gets
          puts line.chomp!
        end
        # rubocop:enable AssignmentInCondition
        io.close
        $CHILD_STATUS.to_i
      end
      logger.warn("Finished #{TasteTester::Config.chef_client_command}" +
                  " on #{@name} with status #{status}")
      if status.zero?
        msg = "#{TasteTester::Config.chef_client_command} was successful" +
              ' - please log to the host and confirm all the intended' +
              ' changes were made'
        logger.error msg.upcase
      end
    end

    def get_transport
      case TasteTester::Config.transport
      when 'locallink'
        TasteTester::LocalLink.new
      when 'noop'
        TasteTester::NoOp.new
      else
        TasteTester::SSH.new(@name)
      end
    end

    def test
      logger.warn("Taste-testing on #{@name}")

      if TasteTester::Config.use_ssh_tunnels
        # Nuke any existing tunnels that may be there
        TasteTester::Tunnel.kill(@name)

        # Then setup the tunnel
        @tunnel.run
      end

      serialized_config = Base64.encode64(config).delete("\n")

      # Then setup the testing
      transport = get_transport

      # see if someone else is taste-testing
      transport << we_testing

      transport << 'logger -t taste-tester Moving server into taste-tester' +
        " for #{@user}"
      transport << touchcmd
      # shell redirection is also racy, so make a temporary file first
      transport << "tt=$(mktemp #{TasteTester::Config.chef_config_path}/" +
        "#{TASTE_TESTER_CONFIG}.TMPXXXXXX)"
      transport << "/bin/echo -n \"#{serialized_config}\" | base64 --decode" +
        ' > "${tempconfig}"'
      # then rename it to replace any existing file
      transport << 'mv -f "${tempconfig}" ' +
        "#{TasteTester::Config.chef_config_path}/#{TASTE_TESTER_CONFIG}"
      transport << "( ln -vsf #{TasteTester::Config.chef_config_path}" +
        "/#{TASTE_TESTER_CONFIG} #{TasteTester::Config.chef_config_path}/" +
        "#{TasteTester::Config.chef_config}; true )"

      # look again to see if someone else is taste-testing. This is where
      # we work out if we won or lost a race with another user.
      transport << we_testing

      transport.run

      case transport.status
      when 0
        # no problem, keep going.
        nil
      when 42
        fail TasteTester::Exceptions::AlreadyTestingError,
             transport.output.chomp
      else
        transport.error!
      end

      # Then run any other stuff they wanted
      cmds = TasteTester::Hooks.test_remote_cmds(
        TasteTester::Config.dryrun,
        @name,
      )

      if cmds&.any?
        transport = get_transport
        cmds.each { |c| transport << c }
        transport.run!
      end
    end

    def untest
      logger.warn("Removing #{@name} from taste-tester")
      transport = get_transport
      if TasteTester::Config.use_ssh_tunnels
        TasteTester::Tunnel.kill(@name)
      end
      config_prod = TasteTester::Config.chef_config.split('.').join('-prod.')
      [
        "ln -vsf #{TasteTester::Config.chef_config_path}/#{config_prod} " +
          "#{TasteTester::Config.chef_config_path}/" +
          TasteTester::Config.chef_config,
        "ln -vsf #{TasteTester::Config.chef_config_path}/client-prod.pem " +
          "#{TasteTester::Config.chef_config_path}/client.pem",
        "rm -vf #{TasteTester::Config.chef_config_path}/#{TASTE_TESTER_CONFIG}",
        "rm -vf #{TasteTester::Config.timestamp_file}",
        'logger -t taste-tester Returning server to production',
      ].each do |cmd|
        transport << cmd
      end
      transport.run!
    end

    def we_testing
      config_file = "#{TasteTester::Config.chef_config_path}/" +
        TasteTester::Config.chef_config
      # Look for signature of TasteTester
      # 1. Look for USER_PREAMBLE line prefix
      # 2. See if user is us, or someone else
      # 3. if someone else is testing: emit username, exit with code 42 which
      #    short circuits the test verb
      # This is written as a squiggly heredoc so the indentation of the awk is
      # preserved. Later we remove the newlines to make it a bit easier to read.
      shellcode = <<~ENDOFSHELLCODE
        awk "\\$0 ~ /^#{USER_PREAMBLE}/{
          if (\\$NF != \\"#{@user}\\"){
            print \\$NF;
            exit 42
          }
        }" #{config_file}
      ENDOFSHELLCODE
      shellcode.delete("\n")
    end

    def keeptesting
      logger.warn("Renewing taste-tester on #{@name} until" +
        " #{TasteTester::Config.testing_end_time.strftime('%y%m%d%H%M.%S')}")
      if TasteTester::Config.use_ssh_tunnels
        TasteTester::Tunnel.kill(@name)
        @tunnel = TasteTester::Tunnel.new(@name, @server)
        @tunnel.run
      else
        transport = get_transport
        transport << touchcmd
        transport.run!
      end
    end

    private

    def touchcmd
      touch = Base64.encode64(
        "if [ 'Darwin' = $(uname) ]; then touch -t \"$(date -r " +
        "#{TasteTester::Config.testing_end_time.to_i} +'%Y%m%d%H%M.%S')\" " +
        "#{TasteTester::Config.timestamp_file}; else touch --date \"$(date " +
        "-d @#{TasteTester::Config.testing_end_time.to_i} +'%Y-%m-%d %T')\" " +
        "#{TasteTester::Config.timestamp_file}; fi",
      ).delete("\n")
      "/bin/echo -n '#{touch}' | base64 --decode | bash"
    end

    def config
      scheme = TasteTester::Config.use_ssl ? 'https' : 'http'
      if TasteTester::Config.use_ssh_tunnels
        url = "#{scheme}://localhost:#{@tunnel.port}"
      else
        url = +"#{scheme}://#{@server.host}"
        url << ":#{TasteTester::State.port}" if TasteTester::State.port
      end
      ttconfig = <<~ENDOFSCRIPT
        #{USER_PREAMBLE}#{@user}
        # Prevent people from screwing up their permissions
        if Process.euid != 0
          puts 'Please run chef as root!'
          Process.exit!
        end

        log_level :info
        log_location STDOUT
        chef_server_url '#{url}'
        ssl_verify_mode :verify_none
        ohai.plugin_path << '#{TasteTester::Config.chef_config_path}/ohai_plugins'
      ENDOFSCRIPT

      extra = TasteTester::Hooks.test_remote_client_rb_extra_code(@name)
      if extra
        ttconfig += <<~ENDOFSCRIPT
          # Begin user-hook specified code
                  #{extra}
          # End user-hook secified code

        ENDOFSCRIPT
      end

      ttconfig += <<~ENDOFSCRIPT
        puts 'INFO: Running on #{@name} in taste-tester by #{@user}'
      ENDOFSCRIPT
      return ttconfig
    end
  end
end
