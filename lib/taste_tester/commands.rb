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
require 'English'

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
      logger.warn('Determining roles which will be impacted by current changes')

      # Get the repository based on the paths specified in config.rb
      repo = BetweenMeals::Repo.get(
        TasteTester::Config.repo_type,
        TasteTester::Config.repo,
        logger,
      )
      if repo && !repo.exists?
        fail "Could not open repo from #{TasteTester::Config.repo}"
      end

      # Compute the set of changes using Between Meals or a custom hook
      if TasteTester::Config.use_custom_changeset_hook
        changeset = TasteTester::Hooks.custom_changeset(repo)
      else
        changeset = _find_changeset(repo)
      end

      # Use the changeset computed earlier to find modified roles
      if TasteTester::Config.use_custom_impact_hook
        impact_roles = TasteTester::Hooks.custom_impact(changeset)
      else
        impact_roles = _find_impact(changeset)
      end

      if impact_roles.empty?
        logger.warn('No impacted roles were found.')
      else
        logger.warn('The following roles have modified dependencies. ' +
                    'Please test a host in each of these roles.')
        impact_roles.each { |r| logger.warn("\t#{r}") }
      end

      # Do any post processing required on the list of impacted roles
      unless TasteTester::Config.skip_post_impact_hook
        TasteTester::Hooks.post_impact(impact_roles)
      end
    end

    def self._find_changeset(repo)
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

      changeset = BetweenMeals::Changeset.new(
        logger,
        repo,
        start_ref,
        nil, # compare with current working copy
        {
          :cookbook_dirs =>
            TasteTester::Config.relative_cookbook_dirs,
          :role_dir =>
            TasteTester::Config.relative_role_dir,
        },
        @track_symlinks,
      )

      return changeset
    end

    def self._find_impact(changeset)
      if TasteTester::Config.relative_cookbook_dirs.length > 1
        logger.error('Knife deps does not support multiple cookbook paths.')
        logger.error('Flatten the repository or use the custom_impact hook.')
        exit(1)
      end

      cookbooks = Set.new(changeset.cookbooks)
      roles = Set.new(changeset.roles)

      if cookbooks.empty? && roles.empty?
        logger.error('No cookbooks or roles have been modified.')
        exit(1)
      end

      unless cookbooks.empty?
        logger.warn('Modified Cookbooks:')
        cookbooks.each { |cb| logger.warn("\t#{cb}") }
      end
      unless roles.empty?
        logger.warn('Modified Roles:')
        roles.each { |r| logger.warn("\t#{r}") }
      end

      return _find_impact_roles(cookbooks, roles)
    end

    def self._find_impact_roles(cookbooks, roles)
      # Now that we have a list of changed cookbooks and roles, we can check
      # which roles contain modified dependencies. For simplicity, we will
      # check using brute force by iterating through each role and comparing
      # its dependencies with the set of modified files. If a match exists,
      # the role was impacted, otherwise we can move on.
      # This may change in the future if it is a perfomance bottleneck.

      role_dir = TasteTester::Config.role_dir
      chef_dir = File.join(TasteTester::Config.repo,
                           TasteTester::Config.base_dir)

      # CLI options for knife call
      config = "--config #{TasteTester::Config.knife_config}"
      chef_path = "--chef-repo-path #{chef_dir}"
      options = '--tree --recurse'

      # shell out to knife once and parse the resulting file for dependents
      # if knife did not exit with 0, print whatever it returned and exit
      logger.warn('Finding dependencies (this may take a minute or two)...')
      knife = Mixlib::ShellOut.new(
        "knife deps /#{role_dir}/*.rb #{options} #{config} #{chef_path}"
      )
      knife.run_command
      if knife.error?
        knife.invalid!('knife deps failed, please check output below')
      end

      # create a hash between roles and their dependencies
      logger.warn('Processing dependencies...')
      deps_tree = _build_dependency_tree(knife.stdout)

      # search the hash for roles containing any modified files
      logger.warn('Searching for impacted roles...')

      impact_roles = []
      roles.each { |r| impact_roles |= r.name }

      deps_tree.each do |r, d|
        cookbooks.each do |cb|
          if d.include?(cb.name)
            impact_roles |= [r]
            logger.info("\tFound dependency: #{r} --> #{cb.name}")
            break
          end
        end
      end

      return impact_roles
    end

    def self._build_dependency_tree(deps)
      # We want to record all nested lines for each role. The top-level roles
      # will not be indented, indicating they have no dependents. Thus, when
      # we see a line without indentation, we can start adding subsequent
      # lines to a list for that line (ie a hash of role -> [deps]). Since we
      # don't care about precise dependencies for cookbooks, we can lump all
      # of the indented layers together into the list for the single role.
      # This is not the most efficient method as repeated cookbooks will list
      # their dependencies multiple times for each role they are part of,
      # but the parsing is significantly easier than building a proper graph.

      tree = {}
      curr_role = nil

      deps.each_line do |line|
        elem = line.rstrip

        if elem.length == elem.lstrip.length
          curr_role = elem
          tree[curr_role] = []
        else
          tree[curr_role] |= [File.basename(elem, File.extname(elem))]
        end
      end

      return tree
    end
  end
end
