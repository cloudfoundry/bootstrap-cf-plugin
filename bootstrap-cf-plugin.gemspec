# -*- encoding: utf-8 -*-
# Copyright (c) 2009-2012 VMware, Inc.

Gem::Specification.new do |s|
  s.name         = "bootstrap-cf-plugin"
  s.version      = '0.0.1'
  s.platform     = Gem::Platform::RUBY
  s.summary      = "CF Bootstrap"
  s.description  = "CF command line tool to bootstrap a CF deployment on top of BOSH"
  s.author       = "VMware"
  s.homepage      = 'https://github.com/cloudfoundry/bootstrap-cf-plugin'
  s.license       = 'Apache 2.0'
  s.email         = "support@cloudfoundry.com"
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.3")

  s.files        = `git ls-files -- lib/* templates/*`.split("\n") + %w(README.md)
  s.require_path = "lib"

  s.add_dependency "bosh_cli_plugin_aws", "~>1.5.0.pre.3"
  s.add_dependency "cf", '~>5.2.2'
  s.add_dependency "haddock"
end
