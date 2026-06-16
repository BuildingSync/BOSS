# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require "thor"
require 'BOSS/boss'
require 'BOSS/constants'

module BOSS
  class CLI < Thor
    desc "write_baseline_osw BUILDINGSYNC_FILE", "writes a baseline osw using data from the provided Buildingsync file."
    option :output_path, :required => true, :aliases => "-o", :desc => "path to where the ows gets written. Defaults to '.'"
    option :epw_path, :aliases => "-w", :desc => "path to weather file. If not given, one is derived from the BUILDINGSYNC_FILE."
    option :schema_version, :aliases => "-v", :desc => "version of buildinsync to use. defaults to 2.7"
    option :run, :aliases => "-r", :desc => "if set, will also run the baseline"
    def write_osw(buildingsync_file)
      boss = BOSS::Boss.new(buildingsync_file, options[:output_path], options[:epw_path], options[:schema_version] || ASHRAE90_1)
      boss.write_baseline_osw
      if options[:run]
        puts "running!"
        boss.run_baseline_osw
      end
    end
  end
end
