require "bootstrap-cf-plugin"
require "cfoundry/test_support"
require "cf/test_support"
require "haddock"
require "blue-shell"

def asset(filename)
  File.expand_path("../assets/#{filename}", __FILE__)
end

def stub_invoke(*args)
  described_class.any_instance.stub(:invoke).with(*args)
end

RSpec.configure do |c|
  c.include FakeHomeDir
  c.include CliHelper
  c.include InteractHelper
  c.include ConfigHelper
  c.include BlueShell::Matchers
end

Haddock::Password.diction = File.expand_path("../assets/words.txt", __FILE__)
