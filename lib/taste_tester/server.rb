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
require 'socket'
require 'timeout'

require 'between_meals/util'
require 'taste_tester/config'
require 'taste_tester/state'

module TasteTester
  # Stateless chef-zero server management
  class Server
    include TasteTester::Config
    include TasteTester::Logging
    extend ::BetweenMeals::Util

    attr_accessor :user, :host

    def initialize
      @state = TasteTester::State.new
      @ref_file = TasteTester::Config.ref_file
      ref_dir = File.dirname(File.expand_path(@ref_file))
      @zero_path = TasteTester::Config.chef_zero_path
      unless File.directory?(ref_dir)
        begin
          FileUtils.mkpath(ref_dir)
        rescue => e
          logger.warn("Chef temp dir #{ref_dir} missing and can't be created")
          logger.warn(e)
        end
      end

      @user = ENV['USER']

      # If we are using SSH tunneling listen on localhost, otherwise listen
      # on all addresses - both v4 and v6. Note that on localhost, ::1 is
      # v6-only, so we default to 127.0.0.1 instead.
      if TasteTester::Config.use_ssh_tunnels
        @addr = '127.0.0.1'
        @host = 'localhost'
      else
        @addr = '::'
        begin
          @host = Socket.gethostname
        rescue
          logger.error('Unable to find fqdn')
          exit 1
        end
      end
    end

    def start
      return if TasteTester::Server.running?
      logger.warn('Starting taste-tester server')
      @state.wipe
      write_config
      start_chef_zero
    end

    def stop
      logger.warn('Stopping taste-tester server')
      @state.wipe
      stop_chef_zero
    end

    def restart
      logger.warn('Restarting taste-tester server')
      if TasteTester::Server.running?
        stop_chef_zero
      end
      write_config
      start_chef_zero
    end

    def port
      @state.port
    end

    def port=(port)
      @state.port = port
    end

    def latest_uploaded_ref
      @state.ref
    end

    def latest_uploaded_ref=(ref)
      @state.ref = ref
    end

    def self.running?
      if TasteTester::State.port
        return port_open?(TasteTester::State.port)
      end
      false
    end

    private

    def write_config
      knife = BetweenMeals::Knife.new(
        :logger => logger,
        :user => @user,
        :ssl => TasteTester::Config.use_ssl,
        :host => @host,
        :port => port,
        :role_dir => TasteTester::Config.roles,
        :cookbook_dirs => TasteTester::Config.cookbooks,
        :checksum_dir => TasteTester::Config.checksum_dir,
      )
      knife.write_user_config
    end

    def start_chef_zero
      unless @state.port
        @state.port = TasteTester::Config.chef_port
      end
      logger.info("Starting chef-zero of port #{@state.port}")
      cmd = "#{chef_zero_path} --host #{@addr} --port #{@state.port} -d"
      cmd << ' --ssl' if TasteTester::Config.use_ssl
      Mixlib::ShellOut.new(cmd).run_command.error!
    end

    def stop_chef_zero
      logger.info('Killing your chef-zero instances')
      s = Mixlib::ShellOut.new("pkill -9 -u #{ENV['USER']} -f bin/chef-zero")
      s.run_command
      # You have to give it a moment to stop or the stat fails
      sleep(1)
    end

    def chef_zero_path
      [
        '/opt/chef/bin/chef-zero',
        '/opt/chef/embedded/bin/chef-zero',
      ].each do |path|
        return path if File.exist?(path)
      end
      logger.error("chef-zero not found")
      exit(1)
    end
  end
end
