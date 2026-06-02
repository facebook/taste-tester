# Copyright 2026-present Facebook
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
require_relative '../lib/taste_tester/logging'
require_relative '../lib/taste_tester/config'
require_relative '../lib/taste_tester/server'
require_relative '../lib/taste_tester/tunnel'
require_relative '../lib/taste_tester/commands'

describe TasteTester::Commands do
  let(:config_hash) do
    TasteTester::Config.save(true)
  end

  before do
    TasteTester::Config.restore(config_hash)
  end

  after do
    TasteTester::Config.restore(config_hash)
  end

  describe '#run_reverse_tunnels' do
    it 'starts the local server and uploads when it is not running' do
      TasteTester::Config.servers(['host1'])
      mock_server = instance_double(TasteTester::Server, :port => 1234)
      tunnel1 = instance_double(TasteTester::Tunnel, :run => true)
      signal_handlers = {}

      allow(TasteTester::Server).to receive(:new).and_return(mock_server)
      allow(TasteTester::Server).to receive(:running?).and_return(false)
      allow(TasteTester::Tunnel).to receive(:new).with(
        'host1',
        mock_server,
      ).and_return(tunnel1)
      allow(TasteTester::Tunnel).to receive(:kill).with('host1')
      allow(Signal).to receive(:trap) do |signal_name, signal_handler|
        if signal_handler.respond_to?(:call)
          signal_handlers[signal_name] = signal_handler
        end
        'DEFAULT'
      end
      allow(TasteTester::Commands).to receive(:sleep) do
        signal_handlers['INT'].call
        nil
      end

      expect(TasteTester::Commands).to receive(:upload)

      TasteTester::Commands.run_reverse_tunnels
    end

    it 'does not re-upload when the local server is already running' do
      TasteTester::Config.servers(%w{host1 host2})
      mock_server = instance_double(TasteTester::Server, :port => 1234)
      tunnel1 = instance_double(TasteTester::Tunnel, :run => true)
      tunnel2 = instance_double(TasteTester::Tunnel, :run => true)
      signal_handlers = {}

      allow(TasteTester::Server).to receive(:new).and_return(mock_server)
      allow(TasteTester::Server).to receive(:running?).and_return(true)
      expect(TasteTester::Commands).not_to receive(:upload)
      allow(TasteTester::Tunnel).to receive(:new).with(
        'host1',
        mock_server,
      ).and_return(tunnel1)
      allow(TasteTester::Tunnel).to receive(:new).with(
        'host2',
        mock_server,
      ).and_return(tunnel2)
      expect(TasteTester::Tunnel).to receive(:kill).with('host1').twice
      expect(TasteTester::Tunnel).to receive(:kill).with('host2').twice
      allow(Signal).to receive(:trap) do |signal_name, signal_handler|
        if signal_handler.respond_to?(:call)
          signal_handlers[signal_name] = signal_handler
        end
        'DEFAULT'
      end
      allow(TasteTester::Commands).to receive(:sleep) do
        signal_handlers['INT'].call
        nil
      end

      TasteTester::Commands.run_reverse_tunnels
    end
  end
end
