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

require 'taste_tester/server'
require 'taste_tester/host'
require 'taste_tester/config'
require 'taste_tester/client'
require 'taste_tester/logging'
require 'taste_tester/exceptions'

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
        if TasteTester::Config.no_repo && server.last_upload_time
          logger.warn("Last upload time was #{server.last_upload_time}")
        elsif !TasteTester::Config.no_repo && server.latest_uploaded_ref
          if server.last_upload_time
            logger.warn("Last upload time was #{server.last_upload_time}")
          end
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
        if TasteTester::Config.no_repo
          repo = nil
        else
          repo = BetweenMeals::Repo.get(
            TasteTester::Config.repo_type,
            TasteTester::Config.repo,
            logger,
          )
        end
        if repo && !repo.exists?
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
        begin
          host.test
          tested_hosts << hostname
        rescue TasteTester::Exceptions::AlreadyTestingError => e
          logger.error("User #{e.username} is already testing on #{hostname}")
        end
      end
      unless TasteTester::Config.skip_post_test_hook ||
          TasteTester::Config.linkonly
        TasteTester::Hooks.post_test(TasteTester::Config.dryrun, repo,
                                     tested_hosts)
      end
      # Strictly: hosts and tested_hosts should be sets to eliminate variance in
      # order or duplicates. The exact comparison works here because we're
      # building tested_hosts from hosts directly.
      if tested_hosts == hosts
        # No exceptions, complete success: every host listed is now configured
        # to use our chef-zero instance.
        exit(0)
      end
      if tested_hosts.empty?
        # All requested hosts are being tested by another user. We didn't change
        # their configuration.
        exit(3)
      end
      # Otherwise, we got a mix of success and failure due to being tested by
      # another user. We'll be pessemistic and return an error because the
      # intent to taste test the complete list was not successful.
      # code.
      exit(2)
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
      # On a force-upload rather than try to clean up whatever's on the server
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
    rescue StandardError => exception
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

    def self.impact
      logger.warn('Determine which roles will be impacted by current changes')
      logger.error('Not yet implemented (testing only)')

      repo = BetweenMeals::Repo.get(
        TasteTester::Config.repo_type,
        TasteTester::Config.repo,
        logger,
      )

      if repo && !repo.exists?
        fail "Could not open repo from #{TasteTester::Config.repo}"
      end

      if TasteTester::Config.use_custom_impact_hook
        TasteTester::Hooks.custom_impact(TasteTester::Config.dryrun, repo)
      else
        # We want to compare changes in the current directory (working set)
        # with the "most recent" commit in the VCS. For SVN, this will be the
        # latest commit on the checked out repository (i.e. 'trunk'). Git/Hg
        # may have different tags or labels assigned to the "master" branch,
        # (i.e. 'master', 'stable', etc.) and should be configured if different
        # than the defaults.
        start_ref = ''
        type = repo.class.name.split('::').last
        case type
        when 'Svn'
          start_ref = repo.latest_revision
        when 'Git'
          start_ref = TasteTester::Config.vcs_master_git
        when 'Hg'
          start_ref = TasteTester::Config.vcs_master_hg
        end

        changeset = BetweeenMeals::Changeset.new(
          logger,
          @repo,
          start_ref,
          nil,
          {
            :cookbook_dirs =>
              TasteTester::Config.relative_cookbook_dirs,
            :role_dir =>
              TasteTester::Config.relative_role_dir,
          },
          @track_symlinks,
        )

        cbs = changeset.cookbooks
        roles = changeset.roles

        # Now that we have a list of changed cookbooks and roles, we can check
        # which roles contain modified dependencies. For simplicity, we will
        # check using brute force by iterating through all dependencies of each
        # role. These dependencies are then checked against the changeset until
        # a match is found. If a match exists, the role was impacted, otherwise
        # we can move on. This may change in the future if it proves to be a
        # perfomance bottleneck.

        impact_roles = Set[roles]

        # Check each role in the roles directory
        Dir.each_child(TasteTester::Config.relative_role_dir) { |r|
          logger.info('Checking role ' + r)

          # Use knife to compute the recursive dependencies of this role
          deps = `knife deps --tree --recurse #{TasteTester::Config.role_dir}/#{r}`
          # Check each line of output with changeset
          # If a dependency was changed, add this role and move to the next one
          deps.each_line { |line|
            if cbs.include?(line.strip)
              impact_roles.add(r)
              break
            end
          }
        }

        logger.warn('The following roles have modified dependencies. Please test' +
                    'a host in each of these roles.')
        impact_roles.each {|r| logger.info(r)}

      end

    end
  end
end
