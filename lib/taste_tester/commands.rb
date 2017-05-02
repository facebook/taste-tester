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

# rubocop:disable UnusedBlockArgument, UnusedMethodArgument
require 'taste_tester/server'
require 'taste_tester/host'
require 'taste_tester/config'
require 'taste_tester/client'
require 'taste_tester/logging'

module TasteTester
  # Functionality dispatch
  module Commands
    extend TasteTester::Logging

    def self.start
      server = TasteTester::Server.new
      return if TasteTester::Server.running?
      server.start
    end

    def self.restart
      server = TasteTester::Server.new
      server.restart
    end

    def self.stop
      server = TasteTester::Server.new
      server.stop
    end

    def self.status
      server = TasteTester::Server.new
      if TasteTester::Server.running?
        logger.warn("Local taste-tester server running on port #{server.port}")
        if server.latest_uploaded_ref
          logger.warn('Latest uploaded revision is ' +
            server.latest_uploaded_ref)
        else
          logger.warn('No cookbooks/roles uploads found')
        end
      else
        logger.warn('Local taste-tester server not running')
      end
    end

    def self.test
      hosts = TasteTester::Config.servers
      unless hosts
        logger.warn('You must provide a hostname')
        exit(1)
      end
      unless TasteTester::Config.yes
        printf("Set #{TasteTester::Config.servers} to test mode? [y/N] ")
        ans = STDIN.gets.chomp
        exit(1) unless ans =~ /^[yY](es)?$/
      end
      if TasteTester::Config.linkonly && TasteTester::Config.really
        logger.warn('Skipping upload at user request... potentially dangerous!')
      else
        if TasteTester::Config.linkonly
          logger.warn('Ignoring --linkonly because --really not set')
        end
        upload
      end
      server = TasteTester::Server.new
      unless TasteTester::Config.linkonly
        repo = BetweenMeals::Repo.get(
          TasteTester::Config.repo_type,
          TasteTester::Config.repo,
          logger,
        )
        unless repo.exists?
          fail "Could not open repo from #{TasteTester::Config.repo}"
        end
      end
      unless TasteTester::Config.skip_pre_test_hook ||
          TasteTester::Config.linkonly
        TasteTester::Hooks.pre_test(TasteTester::Config.dryrun, repo, hosts)
      end
      tested_hosts = []
      hosts.each do |hostname|
        host = TasteTester::Host.new(hostname, server)
        if host.in_test?
          username = host.who_is_testing
          logger.error("User #{username} is already testing on #{hostname}")
        else
          host.test
          tested_hosts << hostname
        end
      end
      unless TasteTester::Config.skip_post_test_hook ||
          TasteTester::Config.linkonly
        TasteTester::Hooks.post_test(TasteTester::Config.dryrun, repo,
                                     tested_hosts)
      end
    end

    def self.untest
      hosts = TasteTester::Config.servers
      unless hosts
        logger.error('You must provide a hostname')
        exit(1)
      end
      server = TasteTester::Server.new
      hosts.each do |hostname|
        host = TasteTester::Host.new(hostname, server)
        host.untest
      end
    end

    def self.runchef
      hosts = TasteTester::Config.servers
      unless hosts
        logger.warn('You must provide a hostname')
        exit(1)
      end
      server = TasteTester::Server.new
      hosts.each do |hostname|
        host = TasteTester::Host.new(hostname, server)
        host.run
      end
    end

    def self.keeptesting
      hosts = TasteTester::Config.servers
      unless hosts
        logger.warn('You must provide a hostname')
        exit(1)
      end
      server = TasteTester::Server.new
      hosts.each do |hostname|
        host = TasteTester::Host.new(hostname, server)
        host.keeptesting
      end
    end

    def self.upload
      server = TasteTester::Server.new
      # On a fore-upload rather than try to clean up whatever's on the server
      # we'll restart chef-zero which will clear everything and do a full
      # upload
      if TasteTester::Config.force_upload
        server.restart
      else
        server.start
      end
      client = TasteTester::Client.new(server)
      client.skip_checks = true if TasteTester::Config.skip_repo_checks
      client.force = true if TasteTester::Config.force_upload
      client.upload
    rescue => exception
      # We're trying to recover from common chef-zero errors
      # Most of them happen due to half finished uploads, which leave
      # chef-zero in undefined state
      errors = [
        'Cannot find a cookbook named',
        'Connection reset by peer',
        'Object not found',
      ]
      if errors.any? { |e| exception.to_s.match(/#{e}/im) }
        TasteTester::Config.force_upload = true
        unless @already_retried
          @already_retried = true
          retry
        end
      end
      logger.error('Upload failed')
      logger.error(exception.to_s)
      logger.error(exception.backtrace.join("\n"))
      exit 1
    end
  end
end
