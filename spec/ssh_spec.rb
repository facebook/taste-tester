# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

# Copyright 2020-present Facebook
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'logger'
require 'base64'
require 'between_meals/util'
require_relative '../lib/taste_tester/logging'
require_relative '../lib/taste_tester/exceptions'
require_relative '../lib/taste_tester/ssh_util'
require_relative '../lib/taste_tester/ssh'
require_relative '../lib/taste_tester/config'

describe TasteTester::SSH do
  let(:logger) do
    Logger.new('/dev/null')
  end

  let(:tt_ssh) do
    TasteTester::SSH.new('mock_host')
  end

  context 'test default config' do
    it 'test ssh base command' do
      expect(tt_ssh.ssh_base_cmd).to eq(
        'ssh  ' +
        '-T ' +
        '-o BatchMode=yes ' +
        '-o UserKnownHostsFile=/dev/null ' +
        '-o StrictHostKeyChecking=no ' +
        '-o ConnectTimeout=5',
      )
    end

    it 'test ssh target' do
      expect(tt_ssh.ssh_target).to eq(
        'root@mock_host',
      )
    end

    it 'test build ssh command' do
      expect(tt_ssh.build_ssh_cmd('mock_ssh', ['cmd1', 'cmd2'])).to eq(
        'mock_ssh root@mock_host ' +
        "\"echo 'Y21kMSAmJiBjbWQy' | base64 --decode | bash -x\"",
      )
    end

    it 'test ssh exception message' do
      expect(
        TasteTester::Logging.logger,
      ).to receive(
        :error,
      ).with(
        /ssh.*root@mock_host/,
      )
      expect { tt_ssh.error! }.to raise_error(
        TasteTester::Exceptions::SshError,
      )
    end
  end

  context 'test custom configs linux' do
    before do
      TasteTester::Config.ssh_connect_timeout 10
      TasteTester::Config.jumps 'mock_jump_user@mock_jump_host'
      TasteTester::Config.ssh_command 'mock_ssh_command'
      TasteTester::Config.user 'rossi'
    end

    it 'test ssh base command' do
      expect(tt_ssh.ssh_base_cmd).to eq(
        'mock_ssh_command ' +
        '-J mock_jump_user@mock_jump_host ' +
        '-T ' +
        '-o BatchMode=yes ' +
        '-o UserKnownHostsFile=/dev/null ' +
        '-o StrictHostKeyChecking=no ' +
        '-o ConnectTimeout=10',
      )
    end

    it 'test ssh target' do
      expect(tt_ssh.ssh_target).to eq(
        'rossi@mock_host',
      )
    end

    it 'test build ssh command' do
      expect(tt_ssh.build_ssh_cmd('mock_ssh', ['cmd1', 'cmd2'])).to eq(
        'mock_ssh rossi@mock_host ' +
        "\"echo 'Y21kMSAmJiBjbWQy' | base64 --decode | sudo bash -x\"",
      )
    end

    it 'test ssh exception message' do
      expect(
        TasteTester::Logging.logger,
      ).to receive(
        :error,
      ).with(
        /mock_ssh_command.*mock_jump_user@mock_jump_host.*rossi@mock_host/,
      )
      expect { tt_ssh.error! }.to raise_error(
        TasteTester::Exceptions::SshError,
      )
    end
  end

  context 'test custom configs windows' do
    before do
      TasteTester::Config.windows_target true
    end
    it 'test build ssh command' do
      expect(tt_ssh.build_ssh_cmd('mock_ssh', ['cmd1', 'cmd2'])).to eq(
        'mock_ssh rossi@mock_host ' +
        "'[Text.Encoding]::Utf8.GetString([Convert]::" +
        "FromBase64String('\"'Y21kMSA7IGNtZDI='))\"' " +
        "| powershell.exe -c -; exit $LASTEXITCODE'",
      )
    end
  end
end
