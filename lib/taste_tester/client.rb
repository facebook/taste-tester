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

require 'minitar'
require 'find'
require 'taste_tester/logging'
require 'between_meals/repo'
require 'between_meals/knife'
require 'between_meals/changeset'
require 'chef/log'
require 'chef/cookbook/chefignore'
require 'parallel'
require 'etc'

module TasteTester
  BASE_PATH_INDEX = 0
  RELATIVE_PATH_INDEX = 1
  DESTINATION_PATH_INDEX = 2
  # Client side upload functionality
  # Ties together Repo/Changeset diff logic
  # and Server/Knife uploads
  class Client
    include TasteTester::Logging
    include BetweenMeals::Util

    attr_accessor :force, :skip_checks

    def initialize(server)
      path = File.expand_path(TasteTester::Config.repo)
      logger.warn("Using #{path}")
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
        :role_type => TasteTester::Config.role_type,
        :config => TasteTester::Config.knife_config,
      )
      @knife.write_user_config
      if TasteTester::Config.no_repo
        @repo = nil
      else
        @repo = BetweenMeals::Repo.get(
          TasteTester::Config.repo_type,
          TasteTester::Config.repo,
          logger,
        )
      end
      if @repo && !@repo.exists?
        fail "Could not open repo from #{TasteTester::Config.repo}"
      end

      @track_symlinks = TasteTester::Config.track_symlinks
    end

    def checks
      unless @skip_checks
        TasteTester::Hooks.repo_checks(TasteTester::Config.dryrun, @repo)
      end
    end

    def upload
      head_rev = nil
      if @repo
        head_rev = @repo.head_rev
        checks unless @skip_checks
        logger.info("Last commit: #{head_rev} " +
          "'#{@repo.last_msg.split("\n").first}'" +
          " by #{@repo.last_author[:email]}")
      end

      if @force || !@server.latest_uploaded_ref || !@repo
        logger.info('Full upload forced') if @force
        logger.info('No repo, doing full upload') unless @repo
        unless TasteTester::Config.skip_pre_upload_hook
          TasteTester::Hooks.pre_upload(TasteTester::Config.dryrun,
                                        @repo,
                                        nil,
                                        head_rev)
        end
        time(logger) { full }
        unless TasteTester::Config.skip_post_upload_hook
          TasteTester::Hooks.post_upload(TasteTester::Config.dryrun,
                                         @repo,
                                         nil,
                                         head_rev)
        end
      else
        # Since we also upload the index, we always need to run the
        # diff even if the version we're on is the same as the last
        # revision
        unless TasteTester::Config.skip_pre_upload_hook
          TasteTester::Hooks.pre_upload(TasteTester::Config.dryrun,
                                        @repo,
                                        @server.latest_uploaded_ref,
                                        head_rev)
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
                                         head_rev)
        end
      end

      @server.latest_uploaded_ref = head_rev
      @server.last_upload_time = Time.new.strftime('%Y-%m-%d %H:%M:%S')
    end

    private

    def gen_file_list(path, destination)
      targets = []
      full_path = File.join(File.join(TasteTester::Config.repo, path))
      return unless File.directory?(full_path)
      Dir.chdir(full_path) do
        look_at = ['']
        while (prefix = look_at.pop)
          Dir.glob(File.join("#{prefix}**", '*'), File::FNM_DOTMATCH) do |p|
            sep_index = p.index(File::SEPARATOR)
            minus_first = sep_index.nil? ? '' : p[sep_index+1..-1]

            if File.directory?(p)
              # we don't store directories in the tar, but we do want to follow
              # top level symlinked directories as they are used to share
              # cookbooks between codebases.
              if minus_first == '' && File.symlink?(p)
                look_at.push("#{p}#{File::SEPARATOR}")
              end
            else
              targets << [full_path, p, destination]
            end
          end
        end
      end
      targets
    end

    def generate_intermediate_tar(bucket, i, prefix)
      stream = Tempfile.create([prefix, i.to_s, '.tar'], @server.bundle_dir)
      Minitar::Writer.open(stream) do |writer|
        bucket.each do |file_entry|
          file_path = File.join(file_entry[BASE_PATH_INDEX], file_entry[RELATIVE_PATH_INDEX])
          name = File.join(file_entry[DESTINATION_PATH_INDEX], file_entry[RELATIVE_PATH_INDEX])

          sep_index = file_entry[RELATIVE_PATH_INDEX].index(File::SEPARATOR)
          minus_first = sep_index.nil? ? '' : file_entry[RELATIVE_PATH_INDEX][sep_index+1..-1]

          chefignores = Chef::Cookbook::Chefignore.new(file_path)
          next if chefignores.ignored?(file_entry[RELATIVE_PATH_INDEX]) ||
            chefignores.ignored?(minus_first)

          if File.symlink?(file_path)
            # tar handling of filenames > 100 characters gets complex. We'd
            # use split_name from Minitar, but it's a private method. It's
            # reasonable to assume that all symlink names in the bundle are
            # less than 100 characters long. Long term, the version of minitar
            # in chefdk should be upgraded.
            fail 'Add support for long symlink paths' if name.size > 100
            # The version of Minitar included in chefdk does not support
            # symlinks directly. Therefore we use direct writes to the
            # underlying stream to reproduce the symlinks
            symlink = {
              :name => name,
              :mode => 0644,
              :typeflag => '2',
              :size => 0,
              :linkname => File.readlink(file_path),
              :prefix => '',
            }
            stream.write(Minitar::PosixHeader.new(symlink))
          else
            File.open(file_path, 'rb') do |r|
              writer.add_file_simple(
                name, :mode => 0644, :size => File.size(r)
              ) do |d, _opts|
                IO.copy_stream(r, d)
              end
            end
          end
        end

      end
      stream.close
      stream.path
    end

    def assemble_bundle(files)
      dest = File.join(@server.bundle_dir, 'tt.tgz')
      begin
        Tempfile.create(['tt', '.tgz'], @server.bundle_dir) do |tempfile|
          stream = Zlib::GzipWriter.new(tempfile, TasteTester::Config.bundle_compression_level)
          files.sort.each do |chunk_path|
            chunk = File.open(chunk_path, 'rb')
            # don't copy end blocks
            IO.copy_stream(chunk, stream, (chunk.size - 1024))
            chunk.close
          end
          stream.write("\0" * 1024)
          stream.close
          File.rename(tempfile.path, dest)
        end
      rescue Errno::ENOENT
        # Normally the temporary file is renamed to the dest name. If this
        # happens, then the cleanup of of the temporary file doesn't work,
        # but this is fine and expected.
        nil
      end
    end

    def bundle_upload
      puts 'Running bundle upload'
      src_dirs = {
        TasteTester::Config.relative_role_dir => 'roles',
        TasteTester::Config.relative_databag_dir => 'data_bags',
      }
      TasteTester::Config.relative_cookbook_dirs.each do |cb_dir|
        src_dirs[cb_dir] = 'cookbooks'
      end

      file_list = []
      src_dirs.each { |path, dest| file_list += gen_file_list(path, dest) }

      chunks = []
      prefix = Time.now.to_i.to_s
      begin
        processes = TasteTester::Config.bundle_generation_processes || Etc.nprocessors
        if processes > 1
          buckets = file_list.each_slice((file_list.length/processes.to_f).round.to_i).to_a
          chunks = Parallel.map((0...buckets.length), :in_processes => buckets.length) do |i|
            generate_intermediate_tar(buckets[i], i, prefix)
          end
        else
          chunks = [generate_intermediate_tar(file_list, 0, prefix)]
        end
        assemble_bundle(chunks)
      ensure
        Dir.glob("#{@server.bundle_dir}/#{prefix}*") { |f| File.unlink(f) }
      end
    end

    def full
      logger.warn('Doing full upload')
      if TasteTester::Config.bundle
        logger.warn('Creating bundle...')
        bundle_upload
        # only leave early if true (strictly bundle mode only)
        return if TasteTester::Config.bundle == true
      end
      logger.warn('Uploading cookbooks...')
      @knife.cookbook_upload_all
      logger.warn('Uploading roles...')
      @knife.role_upload_all
      logger.warn('Uploading databags...')
      @knife.databag_upload_all
    end

    def partial
      if TasteTester::Config.bundle
        logger.info('No partial support for bundle mode, doing full upload')
        bundle_upload
        return if TasteTester::Config.bundle == true
      end
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
        @track_symlinks,
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
