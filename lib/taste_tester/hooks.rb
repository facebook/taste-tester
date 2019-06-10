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

require 'taste_tester/logging'
require 'between_meals/util'
require 'between_meals/repo/hg'
require 'between_meals/repo/git'

module TasteTester
  # Hooks placeholders
  class Hooks
    extend TasteTester::Logging
    extend BetweenMeals::Util

    # Do stuff before we upload to chef-zero
    def self.pre_upload(_dryrun, _repo, _last_ref, _cur_ref); end

    # Do stuff after we upload to chef-zero
    def self.post_upload(_dryrun, _repo, _last_ref, _cur_ref); end

    # Do stuff before we put hosts in test mode
    def self.pre_test(_dryrun, _repo, _hosts); end

    # This should return an array of commands to execute on
    # remote systems.
    def self.test_remote_cmds(_dryrun, _hostname); end

    # Should return a string with extra stuff to shove
    # in the remote client.rb
    def self.test_remote_client_rb_extra_code(_hostname); end

    # Do stuff after we put hosts in test mode
    def self.post_test(_dryrun, _repo, _hosts); end

    # Additional checks you want to do on the repo
    def self.repo_checks(_dryrun, _repo); end

    # This should return a Set of roles impacted by changes.
    # By default, the format is "/roles/{role}.rb"
    def self.custom_impact(_changeset); end

    # Do stuff after we find impacted roles
    # This should return a Set object with the final impact. To return more
    # complex data, you must also provide a print_impact function which returns
    # true to override the default output.
    def self.post_impact(impacted_roles)
      return impacted_roles
    end

    # Customized the printed output of impact
    # If this method returns true, the default output will not be printed.
    def self.print_impact(_final_impact); end

    # Find the set of roles dependent on the changed files.
    # If returning something other than a set of roles, post_impact and/or
    # print_impact should be specified to handle the output.
    def self.impact_find_roles(changes)
      if TasteTester::Config.relative_cookbook_dirs.length > 1
        logger.error('Knife deps does not support multiple cookbook paths.')
        logger.error('Flatten the repo or override the resolve_deps function.')
        exit(1)
      end

      cookbooks = Set.new(changes.cookbooks)
      roles = Set.new(changes.roles)
      databags = Set.new(changes.databags)

      if cookbooks.empty? && roles.empty?
        logger.warn('No cookbooks or roles have been modified.')
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
        ' --tree --recurse'
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

    def self.get(file)
      path = File.expand_path(file)
      logger.warn("Loading plugin at #{path}")
      unless File.exists?(path)
        logger.error('Plugin file not found')
        exit(1)
      end
      class_eval(File.read(path), path, 1)
    end
  end
end
