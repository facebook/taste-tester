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

# rubocop:disable ClassVars
require 'logger'

module TasteTester
  # Logging wrapper
  module Logging
    @@use_log_formatter = false
    @@level = Logger::WARN
    @@formatter_proc = nil

    def logger
      logger = Logging.logger
      logger.formatter = formatter
      logger.level = @@level
      logger
    end

    def self.logger
      @logger ||= Logger.new(STDOUT)
    end

    def self.formatterproc=(process)
      @@formatter_proc = process
    end

    def self.use_log_formatter=(use_log_formatter)
      @@use_log_formatter = use_log_formatter
    end

    def self.verbosity=(level)
      @@level = level
    end

    def formatter
      return @@formatter_proc if @@formatter_proc

      if @@use_log_formatter
        proc do |severity, datetime, _progname, msg|
          if severity == 'ERROR'
            msg = msg.red
          end
          "[#{datetime.strftime('%Y-%m-%dT%H:%M:%S%:z')}] #{severity}: #{msg}\n"
        end
      else
        proc do |severity, _datetime, _progname, msg|
          msg.dup.to_s.prepend("#{severity}: ") unless severity == 'WARN'
          if severity == 'ERROR'
            msg = msg.to_s.red
          end
          "#{msg}\n"
        end
      end
    end
  end
end
# rubocop:enable ClassVars
