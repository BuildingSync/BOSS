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
    option :standard_version, :aliases => "-v", :desc => "building standard to use (eg ASHRAE90.1 or CaliforniaTitle24). Defaults to ASHRAE90.1"
    option :run, :aliases => "-r", :desc => "if set, will also run the baseline"
    def write_baseline_osw(buildingsync_file)
      standard_version = options[:standard_version] || ASHRAE90_1
      osw_path = BOSS::Boss.write_baseline_osw(buildingsync_file, options[:output_path], options[:epw_path], standard_version)
      puts "Baseline OSW written to: #{osw_path}"
      if options[:run]
        puts "running!"
        BOSS::Boss.run_baseline_osw(options[:output_path])
      end
    end

    desc "run_osw", "runs an existing baseline osw from the output path."
    option :output_path, :required => true, :aliases => "-o", :desc => "path where the baseline osw exists (expects baseline/in.osw)."
    def run_osw
      standard_version = options[:standard_version] || ASHRAE90_1
      BOSS::Boss.run_baseline_osw(options[:output_path])
    end
  end
end
