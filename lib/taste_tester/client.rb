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
require 'between_meals/repo'
require 'between_meals/knife'
require 'between_meals/changeset'

module TasteTester
  # Client side upload functionality
  # Ties together Repo/Changeset diff logic
  # and Server/Knife uploads
  class Client
    include TasteTester::Logging
    include BetweenMeals::Util

    attr_accessor :force, :skip_checks

    def initialize(server)
      @server = server
      @knife = BetweenMeals::Knife.new(
        :logger => logger,
        :user => @server.user,
        :ssl => TasteTester::Config.use_ssl,
        :host => @server.host,
        :port => @server.port,
        :role_dir => TasteTester::Config.roles,
        :cookbook_dirs => TasteTester::Config.cookbooks,
        :databag_dir => TasteTester::Config.databags,
        :checksum_dir => TasteTester::Config.checksum_dir,
      )
      @knife.write_user_config
      @repo = BetweenMeals::Repo.get(
        TasteTester::Config.repo_type,
        TasteTester::Config.repo,
        logger,
      )
      unless @repo.exists?
        fail "Could not open repo from #{TasteTester::Config.repo}"
      end
    end

    def checks
      unless @skip_checks
        TasteTester::Hooks.repo_checks(TasteTester::Config.dryrun, @repo)
      end
    end

    def upload
      checks unless @skip_checks

      logger.warn("Using #{TasteTester::Config.repo}")
      logger.info("Last commit: #{@repo.head_rev} " +
        "'#{@repo.last_msg.split("\n").first}'" +
        " by #{@repo.last_author[:email]}")

      if @force || !@server.latest_uploaded_ref
        logger.info('Full upload forced') if @force
        unless TasteTester::Config.skip_pre_upload_hook
          TasteTester::Hooks.pre_upload(TasteTester::Config.dryrun,
                                        @repo,
                                        nil,
                                        @repo.head_rev)
        end
        time(logger) { full }
        unless TasteTester::Config.skip_post_upload_hook
          TasteTester::Hooks.post_upload(TasteTester::Config.dryrun,
                                         @repo,
                                         nil,
                                         @repo.head_rev)
        end
      else
        # Since we also upload the index, we always need to run the
        # diff even if the version we're on is the same as the last
        # revision
        unless TasteTester::Config.skip_pre_upload_hook
          TasteTester::Hooks.pre_upload(TasteTester::Config.dryrun,
                                        @repo,
                                        @server.latest_uploaded_ref,
                                        @repo.head_rev)
        end
        begin
          time(logger) { partial }
        rescue BetweenMeals::Changeset::ReferenceError
          logger.warn('Something changed with your repo, doing full upload')
          time(logger) { full }
        end
        unless TasteTester::Config.skip_post_upload_hook
          TasteTester::Hooks.post_upload(TasteTester::Config.dryrun,
                                         @repo,
                                         @server.latest_uploaded_ref,
                                         @repo.head_rev)
        end
      end

      @server.latest_uploaded_ref = @repo.head_rev
    end

    private

    def full
      logger.warn('Doing full upload')
      @knife.cookbook_upload_all
      @knife.role_upload_all
      @knife.databag_upload_all
    end

    def partial
      logger.info('Doing differential upload from ' +
                   @server.latest_uploaded_ref)
      changeset = BetweenMeals::Changeset.new(
        logger,
        @repo,
        @server.latest_uploaded_ref,
        nil,
        {
          :cookbook_dirs =>
            TasteTester::Config.relative_cookbook_dirs,
          :role_dir =>
            TasteTester::Config.relative_role_dir,
          :databag_dir =>
            TasteTester::Config.relative_databag_dir,
        },
      )

      cbs = changeset.cookbooks
      deleted_cookbooks = cbs.select { |x| x.status == :deleted }
      modified_cookbooks = cbs.select { |x| x.status == :modified }
      roles = changeset.roles
      deleted_roles = roles.select { |x| x.status == :deleted }
      modified_roles = roles.select { |x| x.status == :modified }
      databags = changeset.databags
      deleted_databags = databags.select { |x| x.status == :deleted }
      modified_databags = databags.select { |x| x.status == :modified }

      didsomething = false
      unless deleted_cookbooks.empty?
        didsomething = true
        logger.warn("Deleting cookbooks: [#{deleted_cookbooks.join(' ')}]")
        @knife.cookbook_delete(deleted_cookbooks)
      end

      unless modified_cookbooks.empty?
        didsomething = true
        logger.warn("Uploading cookbooks: [#{modified_cookbooks.join(' ')}]")
        @knife.cookbook_upload(modified_cookbooks)
      end

      unless deleted_roles.empty?
        didsomething = true
        logger.warn("Deleting roles: [#{deleted_roles.join(' ')}]")
        @knife.role_delete(deleted_roles)
      end

      unless modified_roles.empty?
        didsomething = true
        logger.warn("Uploading roles: [#{modified_roles.join(' ')}]")
        @knife.role_upload(modified_roles)
      end

      unless deleted_databags.empty?
        didsomething = true
        logger.warn("Deleting databags: [#{deleted_databags.join(' ')}]")
        @knife.databag_delete(deleted_databags)
      end

      unless modified_databags.empty?
        didsomething = true
        logger.warn("Uploading databags: [#{modified_databags.join(' ')}]")
        @knife.databag_upload(modified_databags)
      end

      logger.warn('Nothing to upload!') unless didsomething
    end
  end
end
