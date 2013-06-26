require "bootstrap-cf-plugin"
require "cfoundry/test_support"
require "cf/test_support"
require "haddock"
require "blue-shell"

def asset(filename)
  File.expand_path("../assets/#{filename}", __FILE__)
end

def stub_invoke(*args)
  any_instance_of described_class do |cli|
    stub(cli).invoke *args
  end
end

RSpec.configure do |c|
  c.include Fake::FakeMethods

  c.mock_with :rr

  c.include FakeHomeDir
  c.include CliHelper
  c.include InteractHelper
  c.include ConfigHelper
  c.include BlueShell::Matchers
end

Haddock::Password.diction = File.expand_path("../assets/words.txt", __FILE__)
