# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'BOSS/version'

Gem::Specification.new do |spec|
  spec.name          = 'BOSS'
  spec.version       = BOSS::VERSION
  spec.authors       = ['Hannah Eslinger', 'Katherine Fleming']
  spec.email         = ['hannah.eslinger@nlr.gov', 'katherine.fleming@nlr.gov']

  spec.summary       = 'Library for reading, writing, and exporting BuildingSync to OpenStudio'
  spec.description   = 'Library for reading, writing, and exporting BuildingSync to OpenStudio'
  spec.homepage      = 'https://buildingsync.net'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.force_encoding('UTF-8').split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'bin'
  spec.executables   = ['boss']
  spec.require_paths = ['lib']

  spec.add_dependency 'bundler', '~> 2.4.10'
  spec.add_dependency 'openstudio-common-measures', '~> 0.12.3'
  spec.add_dependency 'openstudio-ee', '~> 0.12.5'
  spec.add_dependency 'openstudio-extension', '~> 0.9.4'
  spec.add_dependency 'openstudio-model-articulation', '~> 0.12.2'
  spec.add_dependency 'httparty', '~> 0.23.2'
  spec.add_dependency 'thor', '~> 1.5.0'

  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'pry', '~> 0.15.2'
end
