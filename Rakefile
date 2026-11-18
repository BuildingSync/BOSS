# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require_relative './lib/BOSS/constants'
require_relative './lib/BOSS/external_measure_repo_manager'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'
RuboCop::RakeTask.new

task default: :spec

namespace :measures do
  desc 'Clone/fetch external non-gem measure repositories declared in config/external_measure_repos.yml'
  task :install_external do
    manager = BOSS::ExternalMeasureRepoManager.new

    if !manager.manifest_exists?
      puts "No external measure manifest found at #{EXTERNAL_MEASURE_REPOS_MANIFEST_PATH}"
      next
    end

    dirs = manager.install_all
    puts "Installed external measure roots (#{dirs.length}):"
    dirs.each { |dir| puts "  - #{dir}" }
  end

  desc 'List resolved external non-gem measure directories'
  task :list_external do
    manager = BOSS::ExternalMeasureRepoManager.new
    dirs = manager.resolved_measure_directories

    puts "External measure roots (#{dirs.length}):"
    dirs.each { |dir| puts "  - #{dir}" }
  end
end