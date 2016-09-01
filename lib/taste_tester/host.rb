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
require 'taste_tester/locallink'
require 'taste_tester/tunnel'

module TasteTester
  # Manage state of the remote node
  class Host
    include TasteTester::Logging

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
      if TasteTester::Config.locallink
        transport = TasteTester::LocalLink.new()
      else
        transport = TasteTester::SSH.new(@name)
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

      @serialized_config = Base64.encode64(config).delete("\n")

      # Then setup the testing
      transport = get_transport

      transport << 'logger -t taste-tester Moving server into taste-tester' +
        " for #{@user}"
      transport << "touch -t #{TasteTester::Config.testing_end_time}" +
        " #{TasteTester::Config.timestamp_file}"
      transport << "echo -n '#{@serialized_config}' | base64 --decode" +
        " > #{TasteTester::Config.chef_config_path}/client-taste-tester.rb"
      transport << "rm -vf #{TasteTester::Config.chef_config_path}/" +
        TasteTester::Config.chef_config
      transport << "( ln -vs #{TasteTester::Config.chef_config_path}" +
        "/client-taste-tester.rb #{TasteTester::Config.chef_config_path}/" +
        "#{TasteTester::Config.chef_config}; true )"
      transport.run!

      # Then run any other stuff they wanted
      cmds = TasteTester::Hooks.test_remote_cmds(
        TasteTester::Config.dryrun,
        @name,
      )

      if cmds && cmds.any?
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
        "rm -vf #{TasteTester::Config.chef_config_path}/" +
          TasteTester::Config.chef_config,
        "rm -vf #{TasteTester::Config.chef_config_path}/client-taste-tester.rb",
        "ln -vs #{TasteTester::Config.chef_config_path}/#{config_prod} " +
          "#{TasteTester::Config.chef_config_path}/" +
          TasteTester::Config.chef_config,
        "rm -vf #{TasteTester::Config.chef_config_path}/client.pem",
        "ln -vs #{TasteTester::Config.chef_config_path}/client-prod.pem " +
          "#{TasteTester::Config.chef_config_path}/client.pem",
        "rm -vf #{TasteTester::Config.timestamp_file}",
        'logger -t taste-tester Returning server to production',
      ].each do |cmd|
        transport << cmd
      end
      transport.run!
    end

    def who_is_testing
      transport = get_transport
      transport << 'grep "^# TasteTester by"' +
        " #{TasteTester::Config.chef_config_path}/" +
        TasteTester::Config.chef_config
      output = transport.run
      if output.first.zero?
        user = output.last.match(/# TasteTester by (.*)$/)
        if user
          return user[1]
        end
      end

      # Legacy FB stuff, remove after migration. Safe for everyone else.
      transport = get_transport
      transport << "file #{TasteTester::Config.chef_config_path}/" +
        TasteTester::Config.chef_config
      output = transport.run
      if output.first.zero?
        user = output.last.match(/client-(.*)-(taste-tester|test).rb/)
        if user
          return user[1]
        end
      end

      return nil
    end

    def in_test?
      transport = get_transport
      transport << "test -f #{TasteTester::Config.timestamp_file}"
      if transport.run.first.zero? && who_is_testing &&
          who_is_testing != ENV['USER']
        true
      else
        false
      end
    end

    def keeptesting
      logger.warn("Renewing taste-tester on #{@name} until" +
        " #{TasteTester::Config.testing_end_time}")
      if TasteTester::Config.use_ssh_tunnels
        TasteTester::Tunnel.kill(@name)
        @tunnel = TasteTester::Tunnel.new(@name, @server)
        @tunnel.run
      else
        transport = get_transport
        transport << "touch -t #{TasteTester::Config.testing_end_time}" +
          " #{TasteTester::Config.timestamp_file}"
        transport.run!
      end
    end

    private

    def config
      scheme = TasteTester::Config.use_ssl ? 'https' : 'http'
      if TasteTester::Config.use_ssh_tunnels
        url = "#{scheme}://localhost:#{@tunnel.port}"
      else
        url = "#{scheme}://#{@server.host}"
        url << ":#{TasteTester::State.port}" if TasteTester::State.port
      end
      # rubocop:disable Metrics/LineLength
      ttconfig = <<-eos
# TasteTester by #{@user}
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

eos
      # rubocop:enable Metrics/LineLength

      extra = TasteTester::Hooks.test_remote_client_rb_extra_code(@name)
      if extra
        ttconfig += <<-eos
# Begin user-hook specified code
        #{extra}
# End user-hook secified code

        eos
      end

      ttconfig += <<-eos
puts 'INFO: Running on #{@name} in taste-tester by #{@user}'
      eos
      return ttconfig
    end
  end
end
