require 'json'
require 'rexml/document'

require 'BOSS/buildingsync_reader/buildingsync_reader'
require 'BOSS/osw_arg_populator'

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

      # write to file
      workflow_dir = File.join(@output_dir, 'baseline')
      FileUtils.mkdir_p(workflow_dir)
      File.open(File.join(workflow_dir, 'in.osw'), 'w') do |file|
        file << JSON.pretty_generate(baseline_osw)
      end
    end

    def run_baseline_osw
    end
  end
end
