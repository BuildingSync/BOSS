# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'tmpdir'
require 'json'
require 'BOSS/constants'
require 'BOSS/boss'

BOSS_SPEC_FILES_DIR = File.expand_path('../../files', __dir__)

RSpec.describe BOSS::Boss do
  # A minimal real XML that Boss.new can parse without errors.
  let(:xml_path) { File.join(BOSS_SPEC_FILES_DIR, 'v2.7.0', 'building_151.xml') }

  # Placeholder paths that represent the three tiers.
  let(:gem_measure_dir)      { '/fake/gem/measures' }
  let(:external_measure_dir) { '/fake/external/measures' }

  before do
    # Prevent real weather file downloads triggered by BuildingSyncReader.
    allow(BOSS::BCLWeatherFileDownloader)
      .to receive(:download_weather_file_from_city_name)
      .and_return(openstudio_weather_file_path)

    # Stub all OSWArgPopulator class methods so they are no-ops; we only care
    # about measure_paths ordering, not the steps payload.
    [
      :populate_set_run_period_args,
      :populate_change_building_location_args,
      :populate_create_bar_from_building_type_ratios_args,
      :populate_create_typical_building_from_model_args,
      :populate_set_lighting_loads_by_LPD_args,
      :populate_set_electric_equipment_loads_by_epd_args,
      :populate_openstudio_results_args
    ].each { |m| allow(OSWArgPopulator).to receive(m) }
  end

  describe '#write_baseline_osw measure_paths ordering' do
    it 'places local measures first, then gem-provided measures, then external repo measures' do
      Dir.mktmpdir do |output_dir|
        boss = described_class.new(xml_path, output_dir, nil, ASHRAE90_1)

        # Simulate OpenStudio::Extension.configure_osw adding gem-provided paths.
        allow(OpenStudio::Extension).to receive(:configure_osw) do |osw|
          osw[:measure_paths] = [gem_measure_dir]
        end

        # Control what ExternalMeasureRepoManager reports.
        fake_manager = instance_double(BOSS::ExternalMeasureRepoManager)
        allow(BOSS::ExternalMeasureRepoManager).to receive(:new).and_return(fake_manager)
        allow(fake_manager).to receive(:local_measure_directories).and_return([LOCAL_MEASURES_DIR])
        allow(fake_manager).to receive(:resolved_measure_directories).and_return([external_measure_dir])

        osw_path = boss.write_baseline_osw

        osw = JSON.parse(File.read(osw_path), symbolize_names: true)
        measure_paths = osw[:measure_paths]

        local_idx    = measure_paths.index(LOCAL_MEASURES_DIR)
        gem_idx      = measure_paths.index(gem_measure_dir)
        external_idx = measure_paths.index(external_measure_dir)

        expect(local_idx).not_to    be_nil, "local measures dir should appear in measure_paths"
        expect(gem_idx).not_to      be_nil, "gem measures dir should appear in measure_paths"
        expect(external_idx).not_to be_nil, "external repo measures dir should appear in measure_paths"

        expect(local_idx).to   be < gem_idx,      "local measures must come before gem measures"
        expect(gem_idx).to     be < external_idx,  "gem measures must come before external repo measures"
      end
    end

    it 'omits external repo dir when no external repos are configured' do
      Dir.mktmpdir do |output_dir|
        boss = described_class.new(xml_path, output_dir, nil, ASHRAE90_1)

        allow(OpenStudio::Extension).to receive(:configure_osw) do |osw|
          osw[:measure_paths] = [gem_measure_dir]
        end

        fake_manager = instance_double(BOSS::ExternalMeasureRepoManager)
        allow(BOSS::ExternalMeasureRepoManager).to receive(:new).and_return(fake_manager)
        allow(fake_manager).to receive(:local_measure_directories).and_return([LOCAL_MEASURES_DIR])
        allow(fake_manager).to receive(:resolved_measure_directories).and_return([])

        osw_path = boss.write_baseline_osw

        measure_paths = JSON.parse(File.read(osw_path), symbolize_names: true)[:measure_paths]
        expect(measure_paths).to include(LOCAL_MEASURES_DIR)
        expect(measure_paths).to include(gem_measure_dir)
        expect(measure_paths).not_to include(external_measure_dir)
      end
    end

    it 'does not duplicate paths that appear in both gem output and local dirs' do
      Dir.mktmpdir do |output_dir|
        boss = described_class.new(xml_path, output_dir, nil, ASHRAE90_1)

        # Extension reports the local dir again (can happen with some gem setups).
        allow(OpenStudio::Extension).to receive(:configure_osw) do |osw|
          osw[:measure_paths] = [LOCAL_MEASURES_DIR, gem_measure_dir]
        end

        fake_manager = instance_double(BOSS::ExternalMeasureRepoManager)
        allow(BOSS::ExternalMeasureRepoManager).to receive(:new).and_return(fake_manager)
        allow(fake_manager).to receive(:local_measure_directories).and_return([LOCAL_MEASURES_DIR])
        allow(fake_manager).to receive(:resolved_measure_directories).and_return([external_measure_dir])

        osw_path = boss.write_baseline_osw

        measure_paths = JSON.parse(File.read(osw_path), symbolize_names: true)[:measure_paths]
        expect(measure_paths.count(LOCAL_MEASURES_DIR)).to eq 1
      end
    end
  end
end
