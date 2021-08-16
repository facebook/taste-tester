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
require_relative '../lib/taste_tester/tunnel'
require_relative '../lib/taste_tester/config'
require_relative '../lib/taste_tester/server'

describe TasteTester::Tunnel do
  let(:logger) do
    Logger.new('/dev/null')
  end

  let(:config_hash) do
    TasteTester::Config.save(true)
  end

  before do
    TasteTester::Config.restore(config_hash)
  end

  before do
    allow_any_instance_of(
      TasteTester::Server,
    ).to receive(:port).and_return(1234)
  end

  let(:mock_server) do
    TasteTester::Server.new
  end

  let(:tt_tunnel) do
    TasteTester::Tunnel.new('mock_host', mock_server)
  end

  context 'test base configs' do
    it 'test build tunnel command' do
      expect(tt_tunnel.cmd).to include(
        'ssh  ' +
        '-T ' +
        '-o BatchMode=yes ' +
        '-o UserKnownHostsFile=/dev/null ' +
        '-o StrictHostKeyChecking=no ' +
        '-o ConnectTimeout=5 ' +
        '-o ServerAliveInterval=10 ' +
        '-o ServerAliveCountMax=6 ' +
        '-f ' +
        '-R 4001:localhost:1234 ' +
        'root@mock_host',
      )
      expect(tt_tunnel.cmd).to include(
        '| base64 --decode | bash -x',
      )
    end
    after do
      TasteTester::Config.restore(config_hash)
    end
  end

  context 'test custom configs linux' do
    before do
      TasteTester::Config.ssh_connect_timeout 10
      TasteTester::Config.jumps 'mock_jump_user@mock_jump_host'
      TasteTester::Config.ssh_command 'mock_ssh_command'
      TasteTester::Config.user 'rossi'
    end

    it 'test build tunnel command' do
      expect(tt_tunnel.cmd).to include(
        'mock_ssh_command ' +
        '-J mock_jump_user@mock_jump_host ' +
        '-T ' +
        '-o BatchMode=yes ' +
        '-o UserKnownHostsFile=/dev/null ' +
        '-o StrictHostKeyChecking=no ' +
        '-o ConnectTimeout=10 ' +
        '-o ServerAliveInterval=10 ' +
        '-o ServerAliveCountMax=6 ' +
        '-f ' +
        '-R 4001:localhost:1234 ' +
        'rossi@mock_host',
      )
      expect(tt_tunnel.cmd).to include(
        '| base64 --decode | sudo bash -x',
      )
    end
    after do
      TasteTester::Config.restore(config_hash)
    end
  end

  context 'test custom configs windows' do
    before do
      TasteTester::Config.ssh_connect_timeout 10
      TasteTester::Config.jumps 'mock_jump_user@mock_jump_host'
      TasteTester::Config.ssh_command 'mock_ssh_command'
      TasteTester::Config.user 'rossi'
      TasteTester::Config.windows_target true
    end
    it 'test build tunnel command' do
      expect(tt_tunnel.cmd).to include(
        'mock_ssh_command ' +
        '-J mock_jump_user@mock_jump_host ' +
        '-T ' +
        '-o BatchMode=yes ' +
        '-o UserKnownHostsFile=/dev/null ' +
        '-o StrictHostKeyChecking=no ' +
        '-o ConnectTimeout=10 ' +
        '-o ServerAliveInterval=10 ' +
        '-o ServerAliveCountMax=6 ' +
        '-f ' +
        '-R 4001:localhost:1234 ' +
        'rossi@mock_host',
      )
      expect(tt_tunnel.cmd).to include(
        'powershell.exe -c -; exit $LASTEXITCODE',
      )
    end
    after do
      TasteTester::Config.restore(config_hash)
    end
  end
end
