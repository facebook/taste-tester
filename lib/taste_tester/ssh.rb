# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
# 
#   http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

module TasteTester
  # Thin ssh wrapper
  class SSH
    include TasteTester::Logging
    include BetweenMeals::Util

    attr_reader :output

    def initialize(host, timeout = 5, tunnel = false)
      @host = host
      @timeout = timeout
      @tunnel = tunnel
      @cmds = []
    end

    def add(string)
      @cmds << string
    end

    alias_method :<<, :add

    def run
      @status, @output = exec(cmd, logger)
    end

    def run!
      @status, @output = exec!(cmd, logger)
    rescue => e
      # rubocop:disable LineLength
      error = <<-MSG
SSH returned error while connecting to #{TasteTester::Config.user}@#{@host}
The host might be broken or your SSH access is not working properly
Try doing 'ssh -v #{TasteTester::Config.user}@#{@host}' and come back once that works
MSG
      # rubocop:enable LineLength
      error.lines.each { |x| logger.error x.strip }
      logger.error(e.message)
    end

    private

    def cmd
      @cmds.each do |cmd|
        logger.info("Will run: '#{cmd}' on #{@host}")
      end
      cmds = @cmds.join(' && ')
      cmd = "ssh -T -o BatchMode=yes -o ConnectTimeout=#{@timeout} "
      cmd += "#{TasteTester::Config.user}@#{@host} "
      if TasteTester::Config.user != 'root'
        cc = Base64.encode64(cmds).gsub(/\n/, '')
        cmd += "\"echo '#{cc}' | base64 --decode | sudo bash -x\""
      else
        cmd += "\'#{cmds}\'"
      end
      cmd
    end
  end
end
