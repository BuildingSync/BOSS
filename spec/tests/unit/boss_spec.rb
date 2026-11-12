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
  end

  def stub_measure_dirs(local:, external:, discovered:, scenario_only: [])
    allow(OpenStudio::Extension).to receive(:configure_osw) do |osw|
      osw[:measure_paths] = discovered
    end

    fake_manager = instance_double(BOSS::ExternalMeasureRepoManager)
    allow(BOSS::ExternalMeasureRepoManager).to receive(:new).and_return(fake_manager)
    allow(fake_manager).to receive(:local_measure_directories).and_return(local)
    allow(fake_manager).to receive(:resolved_measure_directories).and_return(external)
    allow(fake_manager).to receive(:resolved_measure_directories)
      .with(include_scenario_only: true).and_return(external + scenario_only)
  end

  def build_reader(xml_file_name)
    xml = File.read(File.join(BOSS_SPEC_FILES_DIR, 'v2.7.0', xml_file_name))
    doc = REXML::Document.new(xml, ignore_whitespace_nodes: :all)
    BOSS::BuildingSyncReader.new(doc, openstudio_weather_file_path, ASHRAE90_1)
  end

  def common_steps(climate_zone)
    {
      run_period: {
        measure_dir_name: 'set_run_period',
        arguments: { __SKIP__: false, timesteps_per_hour: '4', begin_date: '2019-01-01', end_date: '2019-12-31' }
      },
      location: {
        measure_dir_name: 'ChangeBuildingLocation',
        arguments: { __SKIP__: false, weather_file_name: File.expand_path(openstudio_weather_file_path), climate_zone: }
      },
      results: { measure_dir_name: 'openstudio_results', arguments: { __SKIP__: false, reg_monthly_details: true } }
    }
  end

  let(:building_151_steps) do
    common = common_steps('ASHRAE 169-2013-3C')
    [
      common[:run_period],
      common[:location],
      {
        measure_dir_name: 'create_bar_from_building_type_ratios',
        arguments: {
          __SKIP__: false, bldg_type_a: 'RetailStandalone', total_bldg_floor_area: 69452.0, floor_height: 0.0,
          num_stories_above_grade: 1.0, num_stories_below_grade: 0.0, template: 'DOE Ref 1980-2004',
          ns_to_ew_ratio: 3.6732677131179763, story_multiplier_method: 'None'
        }
      },
      {
        measure_dir_name: 'create_typical_building_from_model',
        arguments: { __SKIP__: false, template: 'DOE Ref 1980-2004', system_type: 'Inferred', add_swh: true, add_hvac: true, use_upstream_args: false }
      },
      { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { __SKIP__: true } },
      { measure_dir_name: 'set_electric_equipment_loads_by_epd', arguments: { __SKIP__: true } },
      { measure_dir_name: 'replace_baseline_windows', arguments: { __SKIP__: true } },
      common[:results]
    ]
  end

  let(:all_measures_steps) do
    common = common_steps('ASHRAE 169-2013-5B')
    [
      common[:run_period],
      common[:location],
      {
        measure_dir_name: 'create_bar_from_building_type_ratios',
        arguments: {
          __SKIP__: false, bldg_type_a: 'SmallOffice', total_bldg_floor_area: 15000.0, floor_height: 10.0,
          num_stories_above_grade: 2.0, num_stories_below_grade: 0.0, template: 'DOE Ref 1980-2004',
          ns_to_ew_ratio: 1.5, story_multiplier_method: 'None'
        }
      },
      {
        measure_dir_name: 'create_typical_building_from_model',
        arguments: {
          __SKIP__: false, template: 'DOE Ref 1980-2004', system_type: 'PSZ-AC with gas unit heaters',
          add_swh: true, add_hvac: true, use_upstream_args: false
        }
      },
      { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { __SKIP__: false, lpd: 1.0 } },
      { measure_dir_name: 'set_electric_equipment_loads_by_epd', arguments: { __SKIP__: false, epd: 1.0 } },
      {
        measure_dir_name: 'replace_baseline_windows',
        arguments: { __SKIP__: false, window_pane_type: 'Double - No LowE - Clear - Aluminum', u_value_ip: '0.50', shgc: '0.39', vlt: '0.39' }
      },
      common[:results]
    ]
  end

  describe '.write_baseline_osw generated baseline' do
    before do
      stub_measure_dirs(local: [LOCAL_MEASURES_DIR], external: [external_measure_dir], discovered: [gem_measure_dir])
    end

    {
      'building_151.xml' => :building_151_steps,
      'all_measures_applied_example.xml' => :all_measures_steps
    }.each do |xml_file_name, expected_steps|
      it "keeps every baseline step and argument for #{xml_file_name}" do
        Dir.mktmpdir do |output_dir|
          xml = File.join(BOSS_SPEC_FILES_DIR, 'v2.7.0', xml_file_name)
          osw_path = described_class.write_baseline_osw(xml, output_dir, openstudio_weather_file_path, ASHRAE90_1)

          expect(osw_path).to eq File.join(output_dir, 'baseline', 'in.osw')
          expect(Dir.children(output_dir)).to eq ['baseline']
          expect(Dir.children(File.join(output_dir, 'baseline'))).to eq ['in.osw']

          osw = JSON.parse(File.read(osw_path), symbolize_names: true)
          expect(osw[:steps]).to eq send(expected_steps)
          expect(osw.keys).to eq [:seed_file, :weather_file, :measure_paths, :file_paths, :run_directory, :steps, :name, :description]
          expect(osw.values_at(:seed_file, :weather_file, :run_directory, :name, :description)).to all(be_nil)
        end
      end
    end

    it 'raises the existing error for a missing XML file without writing output' do
      Dir.mktmpdir do |output_dir|
        missing = File.join(output_dir, 'missing.xml')
        expect { described_class.write_baseline_osw(missing, output_dir, nil, ASHRAE90_1) }
          .to raise_error(RuntimeError, "File '#{missing}' does not exist")
        expect(Dir.children(output_dir)).to be_empty
      end
    end

    it 'writes into nested output paths with spaces' do
      Dir.mktmpdir do |tmp|
        output_dir = File.join(tmp, 'nested dir', 'out')
        osw_path = described_class.write_baseline_osw(
          File.join(BOSS_SPEC_FILES_DIR, 'v2.7.0', 'building_151.xml'), output_dir, nil, ASHRAE90_1
        )
        expect(osw_path).to eq File.join(output_dir, 'baseline', 'in.osw')
        expect(File.file?(osw_path)).to be true
      end
    end

    it 'does not run workflows while writing' do
      expect(OpenStudio::Extension::Runner).not_to receive(:new)
      Dir.mktmpdir do |output_dir|
        described_class.write_baseline_osw(File.join(BOSS_SPEC_FILES_DIR, 'v2.7.0', 'building_151.xml'), output_dir, nil, ASHRAE90_1)
      end
    end
  end

  describe '.build_baseline_osw' do
    before do
      stub_measure_dirs(local: [LOCAL_MEASURES_DIR], external: [external_measure_dir], discovered: [gem_measure_dir])
    end

    it 'is private while the public API stays public' do
      expect(described_class.private_methods).to include(:build_baseline_osw)
      expect(described_class.public_methods).to include(:write_baseline_osw, :run_baseline_osw)
      expect(described_class.method(:write_baseline_osw).arity).to eq 4
      expect(described_class.method(:run_baseline_osw).arity).to eq 1
    end

    it 'returns the same steps as the writer without writing files' do
      Dir.mktmpdir do |output_dir|
        Dir.chdir(output_dir) do
          osw = described_class.send(:build_baseline_osw, build_reader('all_measures_applied_example.xml'))
          expect(osw[:steps]).to eq all_measures_steps
          expect(Dir.children(output_dir)).to be_empty
        end
      end
    end

    it 'returns a fresh workflow on every call' do
      reader = build_reader('all_measures_applied_example.xml')
      first = described_class.send(:build_baseline_osw, reader)
      first[:steps].first[:arguments][:timesteps_per_hour] = '1'
      first[:steps] << { measure_dir_name: 'extra', arguments: {} }
      first[:measure_paths] << '/mutated'
      first[:file_paths] << '/mutated'

      second = described_class.send(:build_baseline_osw, reader)
      expect(second[:steps]).to eq all_measures_steps
      expect(second[:measure_paths]).not_to include('/mutated')
      expect(second[:file_paths]).not_to include('/mutated')
    end

    it 'replaces create_typical HVAC with planned topology steps and adds scenario-only measure paths' do
      stub_measure_dirs(local: [LOCAL_MEASURES_DIR], external: [external_measure_dir], discovered: [gem_measure_dir],
                        scenario_only: ['/bsync/measures'])
      steps = [{ measure_dir_name: 'apply_hvac_topology_to_zone_scope', arguments: { topology_measure: 'hvac_ptac' } },
               { measure_dir_name: 'apply_standard_hvac_sizing_and_efficiency', arguments: {} }]
      plan = BOSS::BaselineHvacPlanner::Plan.new(status: :topology, steps: steps, messages: [])
      allow_any_instance_of(BOSS::BaselineHvacPlanner).to receive(:plan).and_return(plan)

      osw = described_class.send(:build_baseline_osw, build_reader('all_measures_applied_example.xml'))
      names = osw[:steps].map { |step| step[:measure_dir_name] }
      typical = names.index('create_typical_building_from_model')

      expect(osw[:steps][typical][:arguments][:add_hvac]).to be false
      expect(names[typical + 1, 2]).to eq(steps.map { |step| step[:measure_dir_name] })
      expect(names - steps.map { |step| step[:measure_dir_name] }).to eq(all_measures_steps.map { |step| step[:measure_dir_name] })
      expect(osw[:measure_paths]).to include('/bsync/measures')
    end
  end

  describe '.write_baseline_osw measure_paths ordering' do
    before do
      # Steps are covered above; these examples only check path ordering.
      [
        :populate_set_run_period_args,
        :populate_change_building_location_args,
        :populate_create_bar_from_building_type_ratios_args,
        :populate_create_typical_building_from_model_args,
        :populate_set_lighting_loads_by_LPD_args,
        :populate_set_electric_equipment_loads_by_epd_args,
        :populate_replace_baseline_windows_args,
        :populate_openstudio_results_args
      ].each { |m| allow(OSWArgPopulator).to receive(m) }
    end

    it 'orders measure_paths and file_paths exactly as local, gem, then external' do
      Dir.mktmpdir do |output_dir|
        stub_measure_dirs(local: ['/fake/local/measures'], external: [external_measure_dir], discovered: [gem_measure_dir])

        osw_path = described_class.write_baseline_osw(xml_path, output_dir, nil, ASHRAE90_1)
        osw = JSON.parse(File.read(osw_path), symbolize_names: true)

        expect(osw[:measure_paths]).to eq ['/fake/local/measures', gem_measure_dir, external_measure_dir]
        expect(osw[:file_paths]).to eq ['/fake/local/files', '/fake/external/files']
      end
    end

    it 'drops nil, empty, and cross-tier duplicate paths without reordering' do
      Dir.mktmpdir do |output_dir|
        stub_measure_dirs(
          local: ['/fake/local/measures'],
          external: [external_measure_dir],
          discovered: [external_measure_dir, nil, '', '/fake/local/measures', gem_measure_dir, gem_measure_dir]
        )

        osw_path = described_class.write_baseline_osw(xml_path, output_dir, nil, ASHRAE90_1)
        osw = JSON.parse(File.read(osw_path), symbolize_names: true)

        expect(osw[:measure_paths]).to eq ['/fake/local/measures', gem_measure_dir, external_measure_dir]
      end
    end
    it 'places local measures first, then gem-provided measures, then external repo measures' do
      Dir.mktmpdir do |output_dir|

        # Simulate OpenStudio::Extension.configure_osw adding gem-provided paths.
        allow(OpenStudio::Extension).to receive(:configure_osw) do |osw|
          osw[:measure_paths] = [gem_measure_dir]
        end

        # Control what ExternalMeasureRepoManager reports.
        fake_manager = instance_double(BOSS::ExternalMeasureRepoManager)
        allow(BOSS::ExternalMeasureRepoManager).to receive(:new).and_return(fake_manager)
        allow(fake_manager).to receive(:local_measure_directories).and_return([LOCAL_MEASURES_DIR])
        allow(fake_manager).to receive(:resolved_measure_directories).and_return([external_measure_dir])

        osw_path = described_class.write_baseline_osw(xml_path, output_dir, nil, ASHRAE90_1)

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

        allow(OpenStudio::Extension).to receive(:configure_osw) do |osw|
          osw[:measure_paths] = [gem_measure_dir]
        end

        fake_manager = instance_double(BOSS::ExternalMeasureRepoManager)
        allow(BOSS::ExternalMeasureRepoManager).to receive(:new).and_return(fake_manager)
        allow(fake_manager).to receive(:local_measure_directories).and_return([LOCAL_MEASURES_DIR])
        allow(fake_manager).to receive(:resolved_measure_directories).and_return([])

        osw_path = described_class.write_baseline_osw(xml_path, output_dir, nil, ASHRAE90_1)

        measure_paths = JSON.parse(File.read(osw_path), symbolize_names: true)[:measure_paths]
        expect(measure_paths).to include(LOCAL_MEASURES_DIR)
        expect(measure_paths).to include(gem_measure_dir)
        expect(measure_paths).not_to include(external_measure_dir)
      end
    end

    it 'does not duplicate paths that appear in both gem output and local dirs' do
      Dir.mktmpdir do |output_dir|

        # Extension reports the local dir again (can happen with some gem setups).
        allow(OpenStudio::Extension).to receive(:configure_osw) do |osw|
          osw[:measure_paths] = [LOCAL_MEASURES_DIR, gem_measure_dir]
        end

        fake_manager = instance_double(BOSS::ExternalMeasureRepoManager)
        allow(BOSS::ExternalMeasureRepoManager).to receive(:new).and_return(fake_manager)
        allow(fake_manager).to receive(:local_measure_directories).and_return([LOCAL_MEASURES_DIR])
        allow(fake_manager).to receive(:resolved_measure_directories).and_return([external_measure_dir])

        osw_path = described_class.write_baseline_osw(xml_path, output_dir, nil, ASHRAE90_1)

        measure_paths = JSON.parse(File.read(osw_path), symbolize_names: true)[:measure_paths]
        expect(measure_paths.count(LOCAL_MEASURES_DIR)).to eq 1
      end
    end
  end

  describe '.write_baseline_and_scenario_osws' do
    let(:building_151_written_ids) do
      ['Scenario1', 'Scenario3', 'Scenario7', 'Scenario8', 'Scenario9', 'Scenario10',
       'Scenario11', 'Scenario12', 'Scenario14', 'Scenario16', 'Scenario24', 'Scenario25']
    end
    let(:led_step) { { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { __SKIP__: false, lpd: 0.6 } } }

    before { allow(BOSS.BOSS_logger).to receive(:warn) }

    # Creates measure.rb sentinels for every measure the shipped map can emit.
    def with_scenario_measure_dir
      Dir.mktmpdir do |dir|
        scenario_measure_dir = File.join(dir, 'measures')
        map = JSON.parse(File.read(SCENARIO_MEASURE_MAP_PATH), symbolize_names: true)
        map[:mappings].flat_map { |mapping| mapping[:steps] }.each do |step|
          FileUtils.mkdir_p(File.join(scenario_measure_dir, step[:measure_dir_name]))
          File.write(File.join(scenario_measure_dir, step[:measure_dir_name], 'measure.rb'), '')
        end
        yield scenario_measure_dir
      end
    end

    def write_building_151(output_dir, scenario_measure_dir)
      stub_measure_dirs(
        local: [LOCAL_MEASURES_DIR], external: [external_measure_dir],
        discovered: [gem_measure_dir], scenario_only: [scenario_measure_dir]
      )
      described_class.write_baseline_and_scenario_osws(xml_path, output_dir, openstudio_weather_file_path, ASHRAE90_1)
    end

    def read_osw(path)
      JSON.parse(File.read(path), symbolize_names: true)
    end

    it 'writes the baseline and one OSW per writable building_151 scenario' do
      with_scenario_measure_dir do |scenario_measure_dir|
        Dir.mktmpdir do |output_dir|
          result = write_building_151(output_dir, scenario_measure_dir)

          expect(result[:baseline_osw_path]).to eq File.join(output_dir, 'baseline', 'in.osw')
          expect(read_osw(result[:baseline_osw_path])[:steps]).to eq building_151_steps
          expect(read_osw(result[:baseline_osw_path])[:measure_paths]).not_to include(scenario_measure_dir)
          expect(Dir.children(output_dir)).to contain_exactly('baseline', 'scenarios')
          expect(Dir.children(File.join(output_dir, 'scenarios'))).to match_array building_151_written_ids

          written, skipped = result[:scenario_results].partition { |scenario| scenario[:status] == :written }
          expect(written.map { |scenario| scenario[:scenario_id] }).to eq building_151_written_ids
          expect(skipped.map { |scenario| scenario[:scenario_id] }).to eq ['Scenario4', 'Scenario5', 'Scenario6', 'Scenario18']
          expect(skipped.map { |scenario| scenario[:osw_path] }).to all(be_nil)
          written.each do |scenario|
            expect(scenario[:osw_path]).to eq File.join(output_dir, 'scenarios', scenario[:scenario_id], 'in.osw')
          end
          expect(result[:parser_warnings]).to be_an Array
        end
      end
    end

    it 'inserts mapped steps before openstudio_results without changing baseline steps' do
      with_scenario_measure_dir do |scenario_measure_dir|
        Dir.mktmpdir do |output_dir|
          result = write_building_151(output_dir, scenario_measure_dir)
          scenario1 = result[:scenario_results].find { |scenario| scenario[:scenario_id] == 'Scenario1' }
          osw = read_osw(scenario1[:osw_path])

          expect(osw[:steps]).to eq building_151_steps[0..-2] + [led_step, building_151_steps.last]
          expect(osw[:steps].map { |step| step.key?(:workflow_phase) }).to all(be false)
          expect(osw[:measure_paths]).to eq [LOCAL_MEASURES_DIR, gem_measure_dir, external_measure_dir, scenario_measure_dir]
          expect(osw[:file_paths].last).to eq File.join(File.dirname(scenario_measure_dir), 'files')
        end
      end
    end

    it 'writes multi-measure package steps in phase order, then reference order' do
      # References are listed out of phase order; two phases have two steps each.
      package = {
        scenario_id: 'MixedPackage', scenario_name: 'Mixed', report_id: 'Report1', package_id: 'PackageMixed',
        scenario_type: :package_of_measures, measure_ids: ['Measure7', 'Measure1', 'Measure9', 'Measure8', 'Measure3']
      }
      allow_any_instance_of(BOSS::BuildingSyncReader).to receive(:get_package_measure_scenarios).and_return([package])

      with_scenario_measure_dir do |scenario_measure_dir|
        Dir.mktmpdir do |output_dir|
          result = write_building_151(output_dir, scenario_measure_dir)
          osw = read_osw(result[:scenario_results].first[:osw_path])
          mapped_steps = osw[:steps][(building_151_steps.length - 1)..-2]

          expect(mapped_steps.map { |step| step[:measure_dir_name] }).to eq [
            'modify_envelope_insulation',              # Measure9, envelope
            'ReduceSpaceInfiltrationByPercentage',     # Measure3, envelope
            'SetLightingLoadsByLPD',                   # Measure1, internal_loads
            'ReduceLightingLoadsByPercentage',         # Measure7, controls_operations
            'ReduceElectricEquipmentLoadsByPercentage' # Measure8, controls_operations
          ]
          expect(mapped_steps[2]).to eq led_step
          expect(osw[:steps].first(building_151_steps.length - 1)).to eq building_151_steps[0..-2]
          expect(osw[:steps].last).to eq building_151_steps.last
        end
      end
    end

    it 'raises before writing anything when a mapped measure is not on measure_paths' do
      Dir.mktmpdir do |output_dir|
        stub_measure_dirs(local: [LOCAL_MEASURES_DIR], external: [external_measure_dir], discovered: [gem_measure_dir])

        expect do
          described_class.write_baseline_and_scenario_osws(xml_path, output_dir, openstudio_weather_file_path, ASHRAE90_1)
        end.to raise_error(StandardError, /not found on measure_paths: .*modify_envelope_insulation.*rake measures:install_external/)
        expect(Dir.children(output_dir)).to be_empty
      end
    end

    it 'writes only the baseline when the file has no package scenarios' do
      Dir.mktmpdir do |output_dir|
        stub_measure_dirs(local: [LOCAL_MEASURES_DIR], external: [external_measure_dir], discovered: [gem_measure_dir])
        xml = File.join(BOSS_SPEC_FILES_DIR, 'v2.7.0', 'building_151_no_measures.xml')

        result = described_class.write_baseline_and_scenario_osws(xml, output_dir, openstudio_weather_file_path, ASHRAE90_1)

        expect(result[:scenario_results]).to eq []
        expect(Dir.children(output_dir)).to eq ['baseline']
      end
    end

    it 'raises the existing error for a missing XML file without writing output' do
      Dir.mktmpdir do |output_dir|
        missing = File.join(output_dir, 'missing.xml')
        expect { described_class.write_baseline_and_scenario_osws(missing, output_dir, nil, ASHRAE90_1) }
          .to raise_error(RuntimeError, "File '#{missing}' does not exist")
        expect(Dir.children(output_dir)).to be_empty
      end
    end
  end

  describe '.order_scenario_steps' do
    it 'sorts by workflow phase, keeps reference order within a phase, and drops workflow_phase' do
      phases = ['envelope', 'internal_loads', 'hvac_equipment', 'controls_operations']
      steps = [
        { measure_dir_name: 'Controls', workflow_phase: 'controls_operations', arguments: {} },
        { measure_dir_name: 'Wall', workflow_phase: 'envelope', arguments: {} },
        { measure_dir_name: 'Lights', workflow_phase: 'internal_loads', arguments: {} },
        { measure_dir_name: 'Roof', workflow_phase: 'envelope', arguments: {} }
      ]

      ordered = described_class.send(:order_scenario_steps, steps, phases)

      expect(ordered).to eq [
        { measure_dir_name: 'Wall', arguments: {} },
        { measure_dir_name: 'Roof', arguments: {} },
        { measure_dir_name: 'Lights', arguments: {} },
        { measure_dir_name: 'Controls', arguments: {} }
      ]
      expect(steps.first).to include(workflow_phase: 'controls_operations')
    end

    it 'keeps reference order when the map declares no phases' do
      steps = [{ measure_dir_name: 'B', arguments: {} }, { measure_dir_name: 'A', arguments: {} }]
      expect(described_class.send(:order_scenario_steps, steps, [])).to eq steps
    end
  end

  describe '.build_scenario_osw' do
    let(:baseline_osw) do
      {
        steps: [
          { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { __SKIP__: false, lpd: 1.0 } },
          { measure_dir_name: 'openstudio_results', arguments: { __SKIP__: false, reg_monthly_details: true } }
        ],
        measure_paths: ['/baseline/measures'], file_paths: ['/baseline/files']
      }
    end
    let(:mapped_steps) do
      [
        { measure_dir_name: 'ReduceElectricEquipmentLoadsByPercentage', arguments: { __SKIP__: false, elecequip_power_reduction_percent: 20.0 } },
        { measure_dir_name: 'ReduceElectricEquipmentLoadsByPercentage', arguments: { __SKIP__: false, elecequip_power_reduction_percent: 5.0 } },
        { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { __SKIP__: false, lpd: 0.6 } }
      ]
    end

    it 'inserts repeated and baseline-named measures without sharing or overwriting arguments' do
      baseline_before = Marshal.load(Marshal.dump(baseline_osw))
      mapped_before = Marshal.load(Marshal.dump(mapped_steps))

      first = described_class.send(:build_scenario_osw, baseline_osw, mapped_steps, ['/s/measures'], ['/s/files'])
      second = described_class.send(:build_scenario_osw, baseline_osw, mapped_steps, ['/s/measures'], ['/s/files'])
      first[:steps][1][:arguments][:elecequip_power_reduction_percent] = 99.0

      expect(second[:steps]).to eq [baseline_before[:steps].first, *mapped_before, baseline_before[:steps].last]
      expect(first[:steps][2]).to eq mapped_before[1]
      expect(baseline_osw).to eq baseline_before
      expect(mapped_steps).to eq mapped_before
      expect(second.values_at(:measure_paths, :file_paths)).to eq [['/s/measures'], ['/s/files']]
    end
  end

  describe '.scenario_output_id_warnings' do
    before { allow(BOSS.BOSS_logger).to receive(:warn) }

    it 'flags missing, unsafe, and case-conflicting IDs and accepts portable IDs' do
      ids = [
        'Scenario1', 'Scenario-2.a_b', nil, '  ', '../escape', 'a/b', 'CON', 'nul.txt', 'trailing.',
        '.hidden', 'Dup', 'dup', 'x' * 65
      ]
      scenarios = ids.map { |id| { scenario_id: id, report_id: 'Report1', package_id: 'Package1' } }

      codes = described_class.send(:scenario_output_id_warnings, scenarios).map { |warning| warning&.fetch(:code) }

      expect(codes).to eq [
        nil, nil, :missing_scenario_output_id, :missing_scenario_output_id,
        :unsafe_scenario_output_id, :unsafe_scenario_output_id, :unsafe_scenario_output_id,
        :unsafe_scenario_output_id, :unsafe_scenario_output_id, :unsafe_scenario_output_id,
        :conflicting_scenario_output_id, :conflicting_scenario_output_id, :unsafe_scenario_output_id
      ]
    end

    it 'returns structured warnings with scenario context' do
      warning = described_class.send(:scenario_output_id_warnings, [{ scenario_id: 'a b', report_id: 'R', package_id: 'P' }]).first

      expect(warning).to include(
        code: :unsafe_scenario_output_id, severity: :warning, report_id: 'R', scenario_id: 'a b', package_id: 'P'
      )
    end
  end

  describe 'running OSWs' do
    let(:runner) { instance_double(OpenStudio::Extension::Runner, run_osws: []) }
    let(:runner_options) { { run_simulations: true, verbose: false, num_parallel: 7, max_to_run: Float::INFINITY } }

    before do
      allow(OpenStudio::Extension::Runner).to receive(:new).and_return(runner)
      allow(BOSS.BOSS_logger).to receive(:warn)
      allow(OpenStudio).to receive(:logFree)
    end

    def touch_osw(*parts)
      path = File.join(*parts, 'in.osw')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, '{}')
      path
    end

    def scenario(id, status, osw_path)
      { scenario_id: id, status:, osw_path:, warnings: [] }
    end

    describe '.run_baseline_osw' do
      it 'runs only baseline/in.osw with the existing runner options and returns failures' do
        Dir.mktmpdir do |dir|
          baseline = touch_osw(dir, 'baseline')
          touch_osw(dir, 'scenarios', 'Scenario1')
          allow(runner).to receive(:run_osws).and_return(['failed'])

          expect(described_class.run_baseline_osw(dir)).to eq ['failed']
          expect(OpenStudio::Extension::Runner).to have_received(:new).with(Dir.pwd, [], runner_options)
          expect(runner).to have_received(:run_osws).with([baseline])
        end
      end

      it 'raises the existing error without building a runner when the baseline is missing' do
        Dir.mktmpdir do |dir|
          expect { described_class.run_baseline_osw(dir) }
            .to raise_error(StandardError, /BOSS\.Boss\.run_baseline_osw: .*write_baseline_osw/)
          expect(OpenStudio::Extension::Runner).not_to have_received(:new)
        end
      end
    end

    describe '.run_baseline_and_scenario_osws' do
      it 'is public with one argument' do
        expect(described_class.method(:run_baseline_and_scenario_osws).arity).to eq 1
        expect(described_class.private_methods).to include(:run_osw_paths)
      end

      it 'runs baseline then written scenarios in result order, skipping stale, missing, and duplicate paths' do
        Dir.mktmpdir do |dir|
          baseline = touch_osw(dir, 'baseline')
          s2 = touch_osw(dir, 'scenarios', 'Scenario 2')
          s1 = touch_osw(dir, 'scenarios', 'Scenario1')
          stale = touch_osw(dir, 'scenarios', 'Stale')
          touch_osw(dir, 'scenarios', 'Unlisted')
          result = {
            baseline_osw_path: baseline,
            scenario_results: [
              scenario('Scenario 2', :written, s2), scenario('Stale', :skipped, stale),
              scenario('Scenario1', :written, s1), scenario('Dup', :written, s1),
              scenario('Gone', :written, File.join(dir, 'scenarios', 'Gone', 'in.osw')),
              scenario('Nil', :written, nil), scenario('Dir', :written, File.join(dir, 'scenarios'))
            ],
            parser_warnings: []
          }
          before = Marshal.load(Marshal.dump(result))

          expect(described_class.run_baseline_and_scenario_osws(result)).to eq []
          expect(runner).to have_received(:run_osws).with([baseline, s2, s1])
          expect(BOSS.BOSS_logger).to have_received(:warn).with(/Gone/)
          expect(BOSS.BOSS_logger).to have_received(:warn).with(/Nil/)
          expect(BOSS.BOSS_logger).to have_received(:warn).with(/Dir/)
          expect(result).to eq before
        end
      end

      it 'runs only the baseline when no scenario was written' do
        Dir.mktmpdir do |dir|
          baseline = touch_osw(dir, 'baseline')
          stale = touch_osw(dir, 'scenarios', 'Scenario4')
          described_class.run_baseline_and_scenario_osws(
            baseline_osw_path: baseline, scenario_results: [scenario('Scenario4', :skipped, stale)]
          )
          expect(runner).to have_received(:run_osws).with([baseline])
        end
      end

      it 'raises before building a runner when the baseline file is missing' do
        Dir.mktmpdir do |dir|
          s1 = touch_osw(dir, 'scenarios', 'Scenario1')
          result = { baseline_osw_path: File.join(dir, 'baseline', 'in.osw'), scenario_results: [scenario('Scenario1', :written, s1)] }

          expect { described_class.run_baseline_and_scenario_osws(result) }
            .to raise_error(StandardError, /run_baseline_and_scenario_osws: .*does not exist/)
          expect(OpenStudio::Extension::Runner).not_to have_received(:new)
        end
      end

      it 'rejects malformed write results' do
        [nil, {}, { baseline_osw_path: ' ', scenario_results: [] }, { baseline_osw_path: 'x', scenario_results: [nil] }].each do |bad|
          expect { described_class.run_baseline_and_scenario_osws(bad) }.to raise_error(ArgumentError)
        end
        expect(OpenStudio::Extension::Runner).not_to have_received(:new)
      end

      it 'propagates runner failures and exceptions' do
        Dir.mktmpdir do |dir|
          result = { baseline_osw_path: touch_osw(dir, 'baseline'), scenario_results: [] }
          allow(runner).to receive(:run_osws).and_raise(RuntimeError, 'boom')
          expect { described_class.run_baseline_and_scenario_osws(result) }.to raise_error(RuntimeError, 'boom')
        end
      end

      it 'runs exactly the baseline and 12 written building_151 scenarios from a real write' do
        stub_measure_dirs(local: [LOCAL_MEASURES_DIR], external: [external_measure_dir], discovered: [gem_measure_dir])
        allow(BOSS::ExternalMeasureRepoManager.new).to receive(:resolved_measure_directories)
          .with(include_scenario_only: true).and_return([external_measure_dir])
        allow(described_class).to receive(:check_scenario_measures_exist)

        Dir.mktmpdir do |dir|
          stale = touch_osw(dir, 'scenarios', 'Scenario4')
          unlisted = touch_osw(dir, 'scenarios', 'Unlisted')
          result = described_class.write_baseline_and_scenario_osws(xml_path, dir, openstudio_weather_file_path, ASHRAE90_1)
          written = result[:scenario_results].select { |s| s[:status] == :written }.map { |s| s[:osw_path] }

          described_class.run_baseline_and_scenario_osws(result)

          expect(written.length).to eq 12
          expect(runner).to have_received(:run_osws).with([result[:baseline_osw_path], *written])
          expect(written).not_to include(stale, unlisted)
        end
      end
    end
  end
end
