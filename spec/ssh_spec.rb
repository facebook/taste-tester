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
require 'mixlib/shellout'
require_relative '../lib/taste_tester/logging'
require_relative '../lib/taste_tester/exceptions'
require_relative '../lib/taste_tester/ssh_util'
require_relative '../lib/taste_tester/ssh'
require_relative '../lib/taste_tester/config'

describe TasteTester::SSH do
  let(:logger) do
    Logger.new('/dev/null')
  end

  let(:config_hash) do
    TasteTester::Config.save(true)
  end

  let(:tt_ssh) do
    TasteTester::SSH.new('mock_host')
  end

  before do
    # THIS IS VERY IMPORTANT!!! If we don't mock **every** call to
    # Mixlibh::ShellOut we can nuke the data on any machine that runs the unit
    # tests so we mock it to return BS, this ensures if we miss mocking a call
    # the tests fail rather than nuking the host
    allow_any_instance_of(Mixlib::ShellOut).to receive(:run_command).
      and_return(nil)
  end

  let(:mock_so) do
    double('shellout')
  end

  before do
    TasteTester::Config.restore(config_hash)
  end
  context 'test default config' do
    it 'test ssh base command' do
      expect(tt_ssh.ssh_base_cmd).to eq(
        'ssh  ' +
        '-T ' +
        '-o BatchMode=yes ' +
        '-o UserKnownHostsFile=/dev/null ' +
        '-o StrictHostKeyChecking=no ' +
        '-o ConnectTimeout=5 ' +
        'root@mock_host',
      )
    end

    it 'test build ssh command' do
      expect(tt_ssh.build_ssh_cmd('mock_ssh_base_cmd', ['cmd1', 'cmd2'])).to eq(
        'mock_ssh_base_cmd ' +
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
    after do
      TasteTester::Config.restore(config_hash)
    end
  end

  context 'test custom ssh configs linux - vanilla ssh command' do
    before do
      TasteTester::Config.ssh_connect_timeout 10
      TasteTester::Config.jumps 'mock_jump_user@mock_jump_host'
      TasteTester::Config.ssh_command 'mock_ssh_cmd'
      TasteTester::Config.user 'rossi'
    end

    it 'test ssh base command' do
      expect(tt_ssh.ssh_base_cmd).to eq(
        'mock_ssh_cmd ' +
        '-J mock_jump_user@mock_jump_host ' +
        '-T ' +
        '-o BatchMode=yes ' +
        '-o UserKnownHostsFile=/dev/null ' +
        '-o StrictHostKeyChecking=no ' +
        '-o ConnectTimeout=10 ' +
        'rossi@mock_host',
      )
    end

    it 'test build ssh command' do
      expect(tt_ssh.build_ssh_cmd('mock_ssh_base_cmd', ['cmd1', 'cmd2'])).to eq(
        'mock_ssh_base_cmd ' +
        "\"echo 'Y21kMSAmJiBjbWQy' | base64 --decode | sudo bash -x\"",
      )
    end

    it 'test ssh exception message' do
      regex_msg = 'SSH returned error ' +
        'while connecting to mock_host' +
        '.*mock_ssh_cmd.*mock_jump_user@mock_jump_host.*rossi@mock_host'
      expect(
        TasteTester::Logging.logger,
      ).to receive(
        :error,
      ).with(
        /#{regex_msg}/m,
      )
      expect { tt_ssh.error! }.to raise_error(
        TasteTester::Exceptions::SshError,
      )
    end
    after do
      TasteTester::Config.restore(config_hash)
    end
  end

  context 'test custom ssh configs linux - generated ssh command' do
    let(:mock_generated_cmd) do
      'mock_ssh_cmd_bin -o option1 -o option2 mock_user@mock_host'
    end

    before do
      TasteTester::Config.ssh_connect_timeout 10
      TasteTester::Config.jumps 'mock_jump_user@mock_jump_host'
      TasteTester::Config.user 'rossi'
      TasteTester::Config.ssh_cmd_gen_template 'mock_generator_cmd ' +
        'mock_arg1 mock_arg2 %{jumps} %{host} --user %{user} --get-command'
      allow(mock_so).to receive(:run_command).and_return(mock_so)
      allow(mock_so).to receive(:error?).and_return(false)
      allow(mock_so).to receive(:error!).and_return(mock_generated_cmd)
      allow(mock_so).to receive(:stderr).and_return('')
      allow(mock_so).to receive(:stdout).and_return(mock_generated_cmd)
    end

    it 'test ssh generated command' do
      expect(tt_ssh.ssh_cmd_generator).to eq(
        'mock_generator_cmd mock_arg1 mock_arg2 ' +
        '-J mock_jump_user@mock_jump_host mock_host ' +
        '--user rossi --get-command',
      )
    end

    it 'test ssh base command' do
      allow(Mixlib::ShellOut).to receive(:new).and_return(mock_so)
      expect(tt_ssh.ssh_base_cmd).to eq(mock_generated_cmd)
    end

    it 'test ssh base command exception' do
      error_message = 'command failure message'
      allow(mock_so).to receive(:error!).and_raise(
        Mixlib::ShellOut::ShellCommandFailed, error_message
      )
      allow(Mixlib::ShellOut).to receive(:new).and_return(mock_so)
      allow(tt_ssh).to receive(:exit).and_raise(StandardError)
      regex_msg = error_message
      expect(
        TasteTester::Logging.logger,
      ).to receive(
        :error,
      ).with(
        /#{regex_msg}/m,
      )
      regex_msg = 'mock_generator_cmd.*failed during execution'
      expect(
        TasteTester::Logging.logger,
      ).to receive(
        :error,
      ).with(
        /#{regex_msg}/m,
      )
      expect { tt_ssh.ssh_base_cmd }.to raise_error(
        StandardError,
      )
    end

    it 'test build ssh command' do
      expect(tt_ssh.build_ssh_cmd(mock_generated_cmd, ['cmd1', 'cmd2'])).to eq(
        "#{mock_generated_cmd} " +
        "\"echo 'Y21kMSAmJiBjbWQy' | base64 --decode | sudo bash -x\"",
      )
    end

    it 'test ssh exception message' do
      allow(Mixlib::ShellOut).to receive(:new).and_return(mock_so)
      expect(tt_ssh.ssh_base_cmd).to eq(mock_generated_cmd)
      regex_msg = 'SSH returned error ' +
        "while connecting to mock_host.*#{mock_generated_cmd}" +
        ".*The above command was generated.*#{tt_ssh.ssh_cmd_generator}"
      expect(
        TasteTester::Logging.logger,
      ).to receive(
        :error,
      ).with(
        /#{regex_msg}/m,
      )
      expect { tt_ssh.error! }.to raise_error(
        TasteTester::Exceptions::SshError,
      )
    end
    after do
      TasteTester::Config.restore(config_hash)
    end
  end

  context 'test custom configs windows' do
    before do
      TasteTester::Config.user 'rossi'
      TasteTester::Config.windows_target true
    end
    it 'test build ssh command' do
      expect(tt_ssh.build_ssh_cmd('mock_ssh_base_cmd', ['cmd1', 'cmd2'])).to eq(
        'mock_ssh_base_cmd ' +
        "'[Text.Encoding]::Utf8.GetString([Convert]::" +
        "FromBase64String('\"'Y21kMSA7IGNtZDI='))\"' " +
        "| powershell.exe -c -; exit $LASTEXITCODE'",
      )
    end
    after do
      TasteTester::Config.restore(config_hash)
    end
  end
end
