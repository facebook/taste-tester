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

module TasteTester
  # State of taste-tester processes
  class State
    include TasteTester::Config
    extend TasteTester::Logging
    include ::BetweenMeals::Util

    def initialize
      ref_dir = File.dirname(File.expand_path(
                               TasteTester::Config.ref_file,
      ))
      unless File.directory?(ref_dir)
        begin
          FileUtils.mkpath(ref_dir)
        rescue => e
          logger.error("Chef temp dir #{ref_dir} missing and can't be created")
          logger.error(e)
          exit(1)
        end
      end
    end

    def port
      TasteTester::State.read(:port)
    end

    def port=(port)
      write(:port, port)
    end

    def ssl
      TasteTester::State.read(:ssl)
    end

    def ssl=(ssl)
      write(:ssl, ssl)
    end

    def logging
      TasteTester::State.read(:logging)
    end

    def logging=(logging)
      write(:logging, logging)
    end

    def ssh
      TasteTester::State.read(:ssh)
    end

    def ssh=(ssh)
      write(:ssh, ssh)
    end

    def ref
      TasteTester::State.read(:ref)
    end

    def ref=(ref)
      write(:ref, ref)
    end

    def update(vals)
      merge(vals)
    end

    def self.port
      TasteTester::State.read(:port)
    end

    def wipe
      if TasteTester::Config.ref_file &&
         File.exists?(TasteTester::Config.ref_file)
        File.delete(TasteTester::Config.ref_file)
      end
    end

    def self.read(key)
      JSON.parse(File.read(TasteTester::Config.ref_file))[key.to_s]
    rescue => e
      logger.debug(e)
      nil
    end

    private_class_method :read

    private

    def write(key, val)
      merge({ key => val })
    end

    def merge(vals)
      begin
        state = JSON.parse(File.read(TasteTester::Config.ref_file))
      rescue
        state = {}
      end
      state.merge!(vals)
      ff = File.open(
        TasteTester::Config.ref_file,
        'w',
      )
      ff.write(state.to_json)
      ff.close
    rescue => e
      logger.error('Unable to write the reffile')
      logger.debug(e)
      exit 0
    end
  end
end
