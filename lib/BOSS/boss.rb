# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'json'
require 'rexml/document'
require 'fileutils'
require 'BOSS/buildingsync_reader/buildingsync_reader'
require 'BOSS/osw_arg_populator'
require 'BOSS/external_measure_repo_manager'

require 'openstudio/common_measures'
require 'openstudio/model_articulation'
require 'openstudio/ee_measures'

module BOSS
  class Boss
    # @param xml_file_path [String]
    # @param output_dir [String]
    # @param epw_file_path [String] if provided, full/path/to/my.epw
    # @param standard_to_be_used [String]
    def initialize(xml_file_path, output_dir, epw_file_path, standard_to_be_used)
      @xml_file_path = xml_file_path
      @output_dir = output_dir
      @epw_file_path = epw_file_path
      @standard_to_be_used = standard_to_be_used

      # check file exists
      if !File.exist?(xml_file_path)
        message = "File '#{xml_file_path}' does not exist"
        OpenStudio.logFree(OpenStudio::Error, 'BOSS.initialize', message)
        raise message
      end

      # open file
      xml_data = File.read(xml_file_path)
      bsync_doc = REXML::Document.new(xml_data, ignore_whitespace_nodes: :all)

      @bsync_reader = BOSS::BuildingSyncReader.new(bsync_doc, epw_file_path, standard_to_be_used)
    end

    def write_baseline_osw
      # start with an empty baseline workflow
      file = File.read(EMPTY_BASELINE_OSW_PATH)
      baseline_osw = JSON.parse(file, symbolize_names: true)

      # populate the baseline measures
      OSWArgPopulator::populate_set_run_period_args(baseline_osw, @bsync_reader)
      OSWArgPopulator::populate_change_building_location_args(baseline_osw, @bsync_reader)

      OSWArgPopulator::populate_create_bar_from_building_type_ratios_args(baseline_osw, @bsync_reader)
      OSWArgPopulator::populate_create_typical_building_from_model_args(baseline_osw, @bsync_reader)

      OSWArgPopulator::populate_set_lighting_loads_by_LPD_args(baseline_osw, @bsync_reader)
      OSWArgPopulator::populate_set_electric_equipment_loads_by_epd_args(baseline_osw, @bsync_reader)
      OSWArgPopulator::populate_openstudio_results_args(baseline_osw, @bsync_reader)

      # Gather extension-derived paths (typically gem-based measures/files) from ObjectSpace.
      OpenStudio::Extension.configure_osw(baseline_osw)

      # Force ordering: local BOSS measures, extension-discovered (gems), then external repos.
      manager = ExternalMeasureRepoManager.new
      local_measure_dirs = manager.local_measure_directories
      external_measure_dirs = manager.resolved_measure_directories
      discovered_measure_dirs = baseline_osw[:measure_paths] || []

      discovered_nonlocal_nonexternal = discovered_measure_dirs.reject do |path|
        local_measure_dirs.include?(path) || external_measure_dirs.include?(path)
      end

      baseline_osw[:measure_paths] = ordered_unique(local_measure_dirs + discovered_nonlocal_nonexternal + external_measure_dirs)

      local_file_paths = local_measure_dirs.map { |path| measure_path_to_files_path(path) }
      external_file_paths = external_measure_dirs.map { |path| measure_path_to_files_path(path) }
      discovered_file_paths = baseline_osw[:file_paths] || []

      discovered_file_nonlocal_nonexternal = discovered_file_paths.reject do |path|
        local_file_paths.include?(path) || external_file_paths.include?(path)
      end

      baseline_osw[:file_paths] = ordered_unique(local_file_paths + discovered_file_nonlocal_nonexternal + external_file_paths)

      # write to file
      workflow_dir = File.join(@output_dir, 'baseline')
      FileUtils.mkdir_p(workflow_dir)
      osw_path = File.join(workflow_dir, 'in.osw')
      File.open(osw_path, 'w') do |file|
        file << JSON.pretty_generate(baseline_osw)
      end
      osw_path
    end

    def run_baseline_osw
      # assert we have a baseline osm
      baseline_osw_path = File.join(@output_dir, 'baseline', 'in.osw')

      #  assert baseline exist
      if !File.file?(baseline_osw_path)
        error_message = (
          "this function requires #{baseline_osw_path}, which does not exist. "\
          "Create #{baseline_osw_path} with `write_baseline_osw` and try again."
        )
        OpenStudio.logFree(OpenStudio::Error, 'BOSS.Boss.run_baseline_osw', error_message)
        raise StandardError, "BOSS.Boss.run_baseline_osw: #{error_message}"
      end

      runner = OpenStudio::Extension::Runner.new(dirname = Dir.pwd, bundle_without = [], options = { run_simulations: true, verbose: false, num_parallel: 7, max_to_run: Float::INFINITY })

      # run the baseline osm
      return runner.run_osws([baseline_osw_path])
    end

    private

    def measure_path_to_files_path(measure_path)
      path = measure_path.to_s
      replaced = path.sub(%r{/measures/?$}, '/files')
      return replaced if replaced != path

      File.expand_path(File.join(path, '..', 'files'))
    end

    def ordered_unique(paths)
      (paths || []).each_with_object([]) do |path, acc|
        next if path.nil? || path.empty? || acc.include?(path)

        acc << path
      end
    end
  end
end
