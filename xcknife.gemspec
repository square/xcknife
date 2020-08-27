# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'xcknife'

Gem::Specification.new do |s|
  s.name          = 'xcknife'
  s.version       = XCKnife::VERSION
  s.authors       = ['Daniel Ribeiro']
  s.email         = %w[danielrb@squareup.com danrbr@gmail.com]
  s.homepage      = 'https://github.com/square/xcknife'
  s.licenses      = ['Apache-2.0']

  s.summary       = 'Simple tool for optimizing XCTest runs across machines'
  s.description   = <<-DESCRIPTION
    Simple tool for optimizing XCTest runs across machines.
    Works by leveraging xctool's json-streams timing and test data.
  DESCRIPTION

  s.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR).reject { |f| f =~ /^spec/ } + ['TestDumper/TestDumper.dylib']
  s.bindir        = 'bin'
  s.executables = %w[xcknife xcknife-min xcknife-test-dumper]
  s.require_paths = ['lib']
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})

  s.required_ruby_version = '>= 2.6.0'

  s.add_development_dependency 'bundler', '~> 1.12'
end
