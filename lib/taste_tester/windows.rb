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

module TasteTester
  module Windows
    def start_win_chef_zero_server
      cmd = "#{TasteTester::Config.chef_zero_path} --port #{@state.port}"

      if TasteTester::Config.my_hostname
        cmd << " --host #{TasteTester::Config.my_hostname}"
      else
        cmd << " --host #{@addr}"
      end
      if TasteTester::Config.chef_zero_logging
        cmd << " --log-file #{@log_file} --log-level debug"
      end
      if TasteTester::Config.use_ssl
        cmd << ' --ssl'
      end

      # Mixlib::Shellout will always wait for a process to finish before
      # returning, so we use `spawn` instead.
      spawn(cmd)
      sleep(2)
    end

    def find_cz_pids
      require 'wmi-lite'
      wmi = WmiLite::Wmi.new
      cz_process_query = %{
        SELECT
          ProcessID
        FROM
          Win32_Process
        WHERE
          CommandLine LIKE "%chef-zero%"
          AND
          Name = "ruby.exe"
      }
      wmi.query(cz_process_query).map do |process|
        process['processid']
      end
    end

    # It is possible to have multiple chef-zero processes running which may
    # mess up taste-tester's state. So... nuke 'em all.
    def nuke_all_cz_pids
      find_cz_pids.each do |pid|
        ::Mixlib::ShellOut.new("taskkill /F /PID #{pid}").run_command
      end
    end
  end
end
