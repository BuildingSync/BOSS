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
require 'BOSS/scenario_measure_mapper'

require 'openstudio/common_measures'
require 'openstudio/model_articulation'
require 'openstudio/ee_measures'

module BOSS
  class Boss
    # Scenario IDs become directory names, so only portable names are written.
    SCENARIO_OUTPUT_ID_PATTERN = /\A[A-Za-z0-9](?:[A-Za-z0-9_.-]{0,62}[A-Za-z0-9_-])?\z/
    WINDOWS_RESERVED_NAME_PATTERN = /\A(?:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|\z)/i

    # @param xml_file_path [String]
    # @param output_dir [String]
    # @param epw_file_path [String] if provided, full/path/to/my.epw
    # @param standard_to_be_used [String]
    class << self
    def write_baseline_osw(xml_file_path, output_dir, epw_file_path, standard_to_be_used)
      # check file exists
      if !File.exist?(xml_file_path)
        message = "File '#{xml_file_path}' does not exist"
        OpenStudio.logFree(OpenStudio::Error, 'BOSS.write_baseline_osw', message)
        raise message
      end

      # open file and prepare to read it
      xml_data = File.read(xml_file_path)
      bsync_doc = REXML::Document.new(xml_data, ignore_whitespace_nodes: :all)
      bsync_reader = BOSS::BuildingSyncReader.new(bsync_doc, epw_file_path, standard_to_be_used)

      baseline_osw = build_baseline_osw(bsync_reader)

      # write to file
      workflow_dir = File.join(output_dir, 'baseline')
      FileUtils.mkdir_p(workflow_dir)
      osw_path = File.join(workflow_dir, 'in.osw')
      File.open(osw_path, 'w') do |file|
        file << JSON.pretty_generate(baseline_osw)
      end
      osw_path
    end

    # Writes baseline/in.osw plus scenarios/<scenario_id>/in.osw for every writable
    # PackageOfMeasures scenario. Nothing is written if a mapped measure cannot be found.
    #
    # @return [Hash] { baseline_osw_path:, scenario_results: [ { scenario_id:, scenario_name:,
    #   report_id:, package_id:, status: :written | :skipped, osw_path:, skipped_measure_ids:,
    #   warnings: } ], parser_warnings: }
    def write_baseline_and_scenario_osws(xml_file_path, output_dir, epw_file_path, standard_to_be_used)
      if !File.exist?(xml_file_path)
        message = "File '#{xml_file_path}' does not exist"
        OpenStudio.logFree(OpenStudio::Error, 'BOSS.write_baseline_and_scenario_osws', message)
        raise message
      end

      bsync_doc = REXML::Document.new(File.read(xml_file_path), ignore_whitespace_nodes: :all)
      bsync_reader = BOSS::BuildingSyncReader.new(bsync_doc, epw_file_path, standard_to_be_used)

      parser_warnings = bsync_reader.get_parser_warnings
      parser_warnings.each do |warning|
        BOSS.BOSS_logger.warn("BOSS.Boss: BuildingSync parser warning: #{warning[:message]} (#{warning.inspect})")
      end

      baseline_osw = build_baseline_osw(bsync_reader)

      manager = ExternalMeasureRepoManager.new
      baseline_dirs = manager.resolved_measure_directories
      all_dirs = manager.resolved_measure_directories(include_scenario_only: true)
      scenario_only_dirs = all_dirs - baseline_dirs
      scenario_measure_paths = ordered_unique(baseline_osw[:measure_paths] + scenario_only_dirs)
      scenario_file_paths = ordered_unique(
        baseline_osw[:file_paths] + scenario_only_dirs.map { |path| measure_path_to_files_path(path) }
      )

      mapper = ScenarioMeasureMapper.new
      context = {
        building_type: bsync_reader.get_building_type_and_bar_division_method.first,
        hvac_system_type: bsync_reader.get_principal_HVAC_system_type
      }
      measures = bsync_reader.get_measures
      scenarios = bsync_reader.get_package_measure_scenarios
      id_warnings = scenario_output_id_warnings(scenarios)

      scenario_results = []
      scenario_osws = []
      mapped_measure_dir_names = []
      scenarios.each_with_index do |scenario, index|
        if id_warnings[index]
          scenario_results << {
            scenario_id: scenario[:scenario_id], scenario_name: scenario[:scenario_name],
            report_id: scenario[:report_id], package_id: scenario[:package_id],
            status: :skipped, osw_path: nil, skipped_measure_ids: [], warnings: [id_warnings[index]]
          }
          next
        end

        mapped = mapper.map_package_scenario(scenario, measures, context:)
        result = mapped.slice(:scenario_id, :scenario_name, :report_id, :package_id)
                       .merge(status: :skipped, osw_path: nil,
                              skipped_measure_ids: mapped[:skipped_measure_ids], warnings: mapped[:warnings])
        scenario_results << result
        next if mapped[:status] != :writable

        mapped_measure_dir_names.concat(mapped[:steps].map { |step| step[:measure_dir_name] })
        scenario_osws << [result, build_scenario_osw(
          baseline_osw, order_scenario_steps(mapped[:steps], mapper.workflow_phases),
          scenario_measure_paths, scenario_file_paths
        )]
      end

      check_scenario_measures_exist(mapped_measure_dir_names, scenario_measure_paths)

      baseline_osw_path = write_osw(File.join(output_dir, 'baseline'), baseline_osw)
      scenario_osws.each do |result, osw|
        result[:osw_path] = write_osw(File.join(output_dir, 'scenarios', result[:scenario_id]), osw)
        result[:status] = :written
      end

      return { baseline_osw_path:, scenario_results:, parser_warnings: }
    end

    # @param osw_dir [String] path to osws
    def run_baseline_osw(osw_dir)
      # assert we have a baseline osm
      baseline_osw_path = File.join(osw_dir, 'baseline', 'in.osw')

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

    # Returns a new, unsaved baseline OSW hash for the given reader.
    def build_baseline_osw(bsync_reader)
      # start with an empty baseline workflow
      file = File.read(EMPTY_BASELINE_OSW_PATH)
      baseline_osw = JSON.parse(file, symbolize_names: true)

      # populate the baseline measures
      OSWArgPopulator::populate_set_run_period_args(baseline_osw, bsync_reader)
      OSWArgPopulator::populate_change_building_location_args(baseline_osw, bsync_reader)

      OSWArgPopulator::populate_create_bar_from_building_type_ratios_args(baseline_osw, bsync_reader)
      OSWArgPopulator::populate_create_typical_building_from_model_args(baseline_osw, bsync_reader)

      OSWArgPopulator::populate_set_lighting_loads_by_LPD_args(baseline_osw, bsync_reader)
      OSWArgPopulator::populate_set_electric_equipment_loads_by_epd_args(baseline_osw, bsync_reader)
      OSWArgPopulator::populate_replace_baseline_windows_args(baseline_osw, bsync_reader)

      OSWArgPopulator::populate_openstudio_results_args(baseline_osw, bsync_reader)

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

      baseline_osw
    end

      def write_osw(workflow_dir, osw)
        FileUtils.mkdir_p(workflow_dir)
        osw_path = File.join(workflow_dir, 'in.osw')
        File.write(osw_path, JSON.pretty_generate(osw))
        osw_path
      end

      # Returns one warning (or nil) per scenario. Every scenario in a group of IDs that
      # differ only by case is skipped, since they would share a directory on Windows/macOS.
      def scenario_output_id_warnings(scenarios)
        warnings = scenarios.map do |scenario|
          scenario_id = scenario[:scenario_id]
          if scenario_id.nil? || scenario_id.to_s.strip.empty?
            [:missing_scenario_output_id, 'Package scenario has no ID; scenario workflow will be skipped.']
          elsif !scenario_id.match?(SCENARIO_OUTPUT_ID_PATTERN) || scenario_id.match?(WINDOWS_RESERVED_NAME_PATTERN)
            [:unsafe_scenario_output_id, 'Package scenario ID is not a safe directory name; scenario workflow will be skipped.']
          end
        end

        safe_indexes = warnings.each_index.select { |index| warnings[index].nil? }
        safe_indexes.group_by { |index| scenarios[index][:scenario_id].downcase }.each_value do |indexes|
          next if indexes.length < 2

          indexes.each do |index|
            warnings[index] = [:conflicting_scenario_output_id,
                               'Package scenario ID conflicts with another scenario ID; scenario workflow will be skipped.']
          end
        end

        warnings.each_with_index.map do |(code, message), index|
          next nil if code.nil?

          scenario = scenarios[index]
          warning = {
            code:, severity: :warning, message:,
            report_id: scenario[:report_id], scenario_id: scenario[:scenario_id], package_id: scenario[:package_id]
          }
          BOSS.BOSS_logger.warn("BOSS.Boss: #{message} (scenario_id: #{scenario[:scenario_id].inspect})")
          warning
        end
      end

      # Stable sort by declared workflow phase, then by package reference order.
      def order_scenario_steps(steps, workflow_phases)
        phase_index = workflow_phases.each_with_index.to_h

        steps.each_with_index
             .sort_by { |step, index| [phase_index.fetch(step[:workflow_phase], workflow_phases.length), index] }
             .map { |step, _index| step.except(:workflow_phase) }
      end

      # Mapped steps go before the trailing openstudio_results reporting step.
      def build_scenario_osw(baseline_osw, mapped_steps, measure_paths, file_paths)
        scenario_osw = Marshal.load(Marshal.dump(baseline_osw))
        steps = scenario_osw[:steps]
        insert_at = steps.index { |step| step[:measure_dir_name] == 'openstudio_results' } || steps.length
        steps.insert(insert_at, *mapped_steps)
        scenario_osw[:measure_paths] = measure_paths.dup
        scenario_osw[:file_paths] = file_paths.dup
        scenario_osw
      end

      def check_scenario_measures_exist(measure_dir_names, measure_paths)
        missing = measure_dir_names.uniq.reject do |name|
          measure_paths.any? { |path| File.file?(File.join(path, name, 'measure.rb')) }
        end
        return if missing.empty?

        message = "Scenario workflows reference measures not found on measure_paths: #{missing.join(', ')}. " \
                  'Run `bundle exec rake measures:install_external` and try again.'
        OpenStudio.logFree(OpenStudio::Error, 'BOSS.write_baseline_and_scenario_osws', message)
        raise StandardError, message
      end

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
end
