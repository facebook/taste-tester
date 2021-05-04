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
        host.runchef
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
      # Use the repository specified in config.rb to calculate the changes
      # that may affect Chef. These changes will be further analyzed to
      # determine specific roles which may change due to modifed dependencies.
      repo = BetweenMeals::Repo.get(
        TasteTester::Config.repo_type,
        TasteTester::Config.repo,
        logger,
      )
      if repo && !repo.exists?
        fail "Could not open repo from #{TasteTester::Config.repo}"
      end

      changes = _find_changeset(repo)

      # Perform preliminary impact analysis. By default, use Knife to find
      # the roles dependent on modified cookbooks. Custom logic may provide
      # additional information by defining the find_impact plugin method.
      basic_impact = TasteTester::Hooks.find_impact(changes)
      basic_impact ||= _find_roles(changes)

      # Do any post processing required on the list of impacted roles, such
      # as looking up hostnames associated with each role. By default, pass
      # the preliminary results through unmodified.
      final_impact = TasteTester::Hooks.post_impact(basic_impact)
      final_impact ||= basic_impact

      # Print the calculated impact. If a print hook is defined that
      # returns true, then the default print function is skipped.
      unless TasteTester::Hooks.print_impact(final_impact)
        _print_impact(final_impact)
      end
    end

    def self._find_changeset(repo)
      # We want to compare changes in the current directory (working set) with
      # the "most recent" commit in the VCS. For SVN, this will be the latest
      # commit on the checked out repository (i.e. 'trunk'). Git/Hg may have
      # different tags or labels assigned to the master branch, (i.e. 'master',
      # 'stable', etc.) and should be configured if different than the default.
      start_ref = case repo
                  when BetweenMeals::Repo::Svn
                    repo.latest_revision
                  when BetweenMeals::Repo::Git
                    TasteTester::Config.vcs_start_ref_git
                  when BetweenMeals::Repo::Hg
                    TasteTester::Config.vcs_start_ref_hg
                  end
      end_ref = TasteTester::Config.vcs_end_ref

      changeset = BetweenMeals::Changeset.new(
        logger,
        repo,
        start_ref,
        end_ref,
        {
          :cookbook_dirs =>
            TasteTester::Config.relative_cookbook_dirs,
          :role_dir =>
            TasteTester::Config.relative_role_dir,
          :databag_dir =>
            TasteTester::Config.relative_databag_dir,
        },
        @track_symlinks,
      )

      return changeset
    end

    def self._find_roles(changes)
      if TasteTester::Config.relative_cookbook_dirs.length > 1
        logger.error('Knife deps does not support multiple cookbook paths.')
        logger.error('Please flatten the cookbooks into a single directory' +
                     ' or define the find_impact method in a local plugin.')
        exit(1)
      end

      cookbooks = Set.new(changes.cookbooks)
      roles = Set.new(changes.roles)
      databags = Set.new(changes.databags)

      if cookbooks.empty? && roles.empty?
        unless TasteTester::Config.json
          logger.warn('No cookbooks or roles have been modified.')
        end
        return Set.new
      end

      unless cookbooks.empty?
        logger.info('Modified Cookbooks:')
        cookbooks.each { |cb| logger.info("\t#{cb}") }
      end
      unless roles.empty?
        logger.info('Modified Roles:')
        roles.each { |r| logger.info("\t#{r}") }
      end
      unless databags.empty?
        logger.info('Modified Databags:')
        databags.each { |db| logger.info("\t#{db}") }
      end

      # Use Knife to list the dependecies for each role in the roles directory.
      # This creates a recursive tree structure that is then searched for
      # instances of modified cookbooks. This can be slow since it must read
      # every line of the Knife output, then search all roles for dependencies.
      # If you have a custom way to calculate these reverse dependencies, this
      # is the part you would replace.
      logger.info('Finding dependencies (this may take a minute or two)...')
      knife = Mixlib::ShellOut.new(
        "knife deps /#{TasteTester::Config.role_dir}/*.rb" +
        " --config #{TasteTester::Config.knife_config}" +
        " --chef-repo-path #{TasteTester::Config.absolute_base_dir}" +
        ' --tree --recurse',
      )
      knife.run_command
      knife.error!

      # Collapse the output from Knife into a hash structure that maps roles
      # to the set of their dependencies. This will ignore duplicates in the
      # Knife output, but must still process each line.
      logger.info('Processing Dependencies...')
      deps_hash = {}
      curr_role = nil

      knife.stdout.each_line do |line|
        elem = line.rstrip
        if elem.length == elem.lstrip.length
          curr_role = elem
          deps_hash[curr_role] = Set.new
        else
          deps_hash[curr_role].add(File.basename(elem, File.extname(elem)))
        end
      end

      # Now we can search for modified dependencies by iterating over each
      # role and checking the hash created earlier. Roles that have been
      # modified directly are automatically included in the impacted set.
      impacted_roles = Set.new(roles.map(&:name))
      deps_hash.each do |role, deplist|
        cookbooks.each do |cb|
          if deplist.include?(cb.name)
            impacted_roles.add(role)
            logger.info("\tFound dependency: #{role} --> #{cb.name}")
            break
          end
        end
      end

      return impacted_roles
    end

    def self._print_impact(final_impact)
      if TasteTester::Config.json
        puts JSON.pretty_generate(final_impact.to_a)
      elsif final_impact.empty?
        logger.warn('No impacted roles were found.')
      else
        logger.warn('The following roles have modified dependencies.' +
                    ' Please test a host in each of these roles.')
        final_impact.each { |r| logger.warn("\t#{r}") }
      end
    end
  end
end
