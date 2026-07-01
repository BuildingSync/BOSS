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
    desc "write_baseline_osw BUILDINGSYNC_FILE", "Writes a baseline osw using data from the provided Buildingsync file."
    long_desc "Example: $ boss write_baseline_osw my_buildingsync.xml -o ./output_dir -w ./specific_weather_file.epw"
    option :output_path, :required => true, :aliases => "-o", :desc => "path to where the ows gets written. Defaults to '.'"
    option :epw_path, :aliases => "-w", :desc => "path to weather file. If not given, one is derived from the BUILDINGSYNC_FILE."
    option :standard_version, :aliases => "-v", :desc => "building standard to use (eg ASHRAE90.1 or CaliforniaTitle24). Defaults to ASHRAE90.1"
    option :run, :aliases => "-r", :desc => "if set, will also run the baseline"
    def write_baseline_osw(buildingsync_file)
      standard_version = options[:standard_version] || ASHRAE90_1
      boss = BOSS::Boss.new(buildingsync_file, options[:output_path], options[:epw_path], standard_version)
      osw_path = boss.write_baseline_osw
      puts "Baseline OSW written to: #{osw_path}"
      if options[:run]
        puts "running!"
        boss.run_baseline_osw
      end
    end

    desc "run_osw BUILDINGSYNC_FILE", "Runs an existing baseline osw from the output path."
    long_desc "Example: $ boss run_osw my_buildingsync.xml -o ./output_dir -w ./specific_weather_file.epw"
    option :output_path, :required => true, :aliases => "-o", :desc => "path where the baseline osw exists (baseline/in.osw will be appended to the path)."
    option :epw_path, :aliases => "-w", :desc => "path to weather file. If not given, one is derived from the BUILDINGSYNC_FILE."
    # option :standard_version, :aliases => "-v", :desc => "building standard to use (eg ASHRAE90.1 or CaliforniaTitle24). Defaults to ASHRAE90.1"
    # todo: we don't really need standard_version at this point, but we need to keep it for now to avoid breaking the CLI interface. We can remove it later.
    def run_osw(buildingsync_file)
      #standard_version = options[:standard_version] || ASHRAE90_1
      boss = BOSS::Boss.new(buildingsync_file, options[:output_path], options[:epw_path], nil)
      boss.run_baseline_osw
    end
  end
end
