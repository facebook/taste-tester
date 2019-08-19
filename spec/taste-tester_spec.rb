require 'spec_helper'
require 'taste_tester/state'

describe TasteTester::State do
  it 'should serialize changes correctly' do
    # initializing a state object creates a directory
    # so let's pretend it already exists.
    allow(File).to receive(:directory?).and_return(true)

    # original state file says ssl -> true
    allow(File).to receive(:read).and_return('{"ssl": true}')
    @s = TasteTester::State.new

    expect(@s.ssl).to eq(true)

    @buffer = StringIO.new
    allow(File).to receive(:open).and_yield(@buffer)
    @s.ssl = false
    expect(@buffer.string).to eq('{"ssl":false}')
  end
end
