# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************
require 'BOSS/constants'
require 'BOSS/boss'

SPEC_FILES_DIR = File.expand_path('../../files', __dir__)
SPEC_OUTPUT_DIR = File.expand_path('../../output', __dir__)

test_configs = [
  # file_name, standard, epw_path, schema_version
  ['all_measures_applied_example.xml', ASHRAE90_1, nil, 'v2.7.0'], # exercises every measure path; uncomment to run full simulation
  ['179D_Example_Building.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['BETTER-1.0.0_SampleOffice_gemtest.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['building_151.xml', ASHRAE90_1, nil, 'v2.7.0'],
  #['BuildingEQ-1.0.0_gemtest.xml', ASHRAE90_1, nil, 'v2.7.0'], # this file errors with the following: [openstudio.model.Model] The run did not finish and had following errors: SizeAirLoopBranches: AirLoopHVAC ZONE MIDRISEAPARTMENT CORRIDOR B END_A - STORY B1 PSZ-AC has air flow less than 1.0000E-003 m3/s.
  ['BuildingEQ-1.0.0.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['Chula_Vista_ASHRAE_L1_Example_Building.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['Demo_ASHRAE_L2_Example_Building.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['Example_ASHRAE_L2_Report_-_with_Energy_Use_Data_2.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['Example_ASHRAE_L2_Report_-_with_Energy_Use_Data.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['Example_ASHRAE_L2_Report.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['Example_HOMES_Template_Building.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['Example_NYC_Energy_Efficiency_Report_Property_2.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['Example_San_Francisco_Audit_Report.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['example-smalloffice-level1.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['Golden Test File.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['L100_Audit-1.0.0_and_BSyncr-1.0.0.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['L100_Audit-1.0.0.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['L100_Pre-Simulation-1.0.0.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['NYC_BBL_AT_Demo_Property.xml', ASHRAE90_1, nil, 'v2.7.0'],
  ['Reference-PrimarySchool-L100-Audit.xml', ASHRAE90_1, nil, 'v2.7.0'],
]

# BOSS_SMOKE=1 runs a small representative subset (used on pull requests).
SMOKE_FILES = ['building_151.xml', 'example-smalloffice-level1.xml'].freeze
test_configs = test_configs.select { |config| SMOKE_FILES.include?(config[0]) } if ENV['BOSS_SMOKE'] == '1'

# BOSS_SHARD / BOSS_SHARDS split the fixtures across parallel CI jobs.
run_extra_examples = ENV['BOSS_SMOKE'] != '1'
if ENV['BOSS_SHARDS']
  shards = Integer(ENV['BOSS_SHARDS'])
  shard = Integer(ENV.fetch('BOSS_SHARD', '0'))
  raise ArgumentError, "BOSS_SHARD must be in 0...#{shards}" if shards < 1 || shard.negative? || shard >= shards

  test_configs = test_configs.select.with_index { |_config, index| index % shards == shard }
  # Examples outside test_configs run once, in shard 0.
  run_extra_examples &&= shard.zero?
end

RSpec.describe 'BOSS' do
  describe 'boss should' do
    before do
      allow(BOSS::BCLWeatherFileDownloader).to receive(:download_weather_file_from_city_name).and_return(openstudio_weather_file_path)
    end

    test_configs.each do |test_config|
      (file_name, standard, epw_path, schema_version) = test_config

      it "write and run baseline osw. File: #{file_name}, Standard: #{standard}, EPW_Path: #{epw_path}, File Schema Version: #{schema_version}" do
        # Set Up
        xml_path = File.join(SPEC_FILES_DIR, schema_version, file_name)
        output_path = File.join(SPEC_OUTPUT_DIR, schema_version, "write_and_run_baseline_osw" , "#{File.basename(xml_path, File.extname(xml_path))}")
        puts output_path

        # Action
        BOSS::Boss.write_baseline_osw(xml_path, output_path, epw_path, standard)
        BOSS::Boss.run_baseline_osw(output_path)

        # Assertion
        puts output_path
        expect(File.exist?(output_path + "/baseline")).to be true
        expect(File.exist?(output_path + "/baseline/out.osw")).to be true
        out_osw = File.read(output_path + "/baseline/out.osw")
        out_osw = JSON.parse(out_osw, symbolize_names: true)
        expect(out_osw[:completed_status]).to eq "Success"
      end

    end

    next unless run_extra_examples

    {
      'example-smalloffice-level2.xml' => ['smalloffice_l2_topology_doe_ref', 'DOE Ref 1980-2004'],
      'example-smalloffice-level2-built-2012.xml' => ['smalloffice_l2_topology', '90.1-2013']
    }.each do |file_name, (output_name, template)|
      it "write and run a topology HVAC baseline. File: #{file_name}, Template: #{template}" do
        xml_path = File.join(SPEC_FILES_DIR, 'v2.7.0', file_name)
        output_path = File.join(SPEC_OUTPUT_DIR, 'v2.7.0', 'write_and_run_baseline_osw', output_name)

        BOSS::Boss.write_baseline_osw(xml_path, output_path, nil, ASHRAE90_1)
        BOSS::Boss.run_baseline_osw(output_path)

        out_osw = JSON.parse(File.read(File.join(output_path, 'baseline', 'out.osw')), symbolize_names: true)
        expect(out_osw[:completed_status]).to eq 'Success'
        steps = out_osw[:steps].to_h { |step| [step[:measure_dir_name], step] }
        expect(steps['create_typical_building_from_model'][:arguments][:add_hvac]).to be false
        topology = steps['apply_hvac_topology_to_zone_scope']
        expect(topology[:result][:step_result]).to eq 'Success'
        expect(topology[:result][:step_final_condition])
          .to match(/Created \d+ PSZ-HP loops \(NaturalGas supplemental heat\).*#{Regexp.escape(template)}/)
        expect(steps['apply_standard_hvac_sizing_and_efficiency'][:result][:step_result]).to eq 'Success'
      end
    end

    it 'write and run an L200 baseline with ComStock recovery' do
      xml_path = File.join(SPEC_FILES_DIR, 'v2.7.0', 'Example_ASHRAE_L2_Report_l200_erv.xml')
      output_path = File.join(SPEC_OUTPUT_DIR, 'v2.7.0', 'write_and_run_baseline_osw', 'ashrae_l2_erv')

      BOSS::Boss.write_baseline_osw(xml_path, output_path, nil, ASHRAE90_1)
      BOSS::Boss.run_baseline_osw(output_path)

      out_osw = JSON.parse(File.read(File.join(output_path, 'baseline', 'out.osw')), symbolize_names: true)
      expect(out_osw[:completed_status]).to eq 'Success'
      names = out_osw[:steps].map { |step| step[:measure_dir_name] }
      tail = ['apply_hvac_topology_to_zone_scope', 'apply_standard_hvac_sizing_and_efficiency',
              'upgrade_hvac_exhaust_air_energy_or_heat_recovery', 'modify_existing_heat_recovery']
      expect(names & tail).to eq tail
      steps = out_osw[:steps].to_h { |step| [step[:measure_dir_name], step] }
      expect(steps['create_typical_building_from_model'][:arguments][:add_hvac]).to be false
      expect(steps['apply_hvac_topology_to_zone_scope'][:result][:step_final_condition]).to match(/PSZ-HP/)
      tail.each { |name| expect(steps[name][:result][:step_result]).to eq('Success'), name }
      affected = steps['upgrade_hvac_exhaust_air_energy_or_heat_recovery'][:result][:step_values]
                 .find { |value| value[:name] == 'hvac_number_of_loops_affected' }
      created = steps['apply_hvac_topology_to_zone_scope'][:result][:step_final_condition][/Created (\d+) PSZ-HP loops/, 1]
      expect(affected[:value]).to eq(created.to_i)
      updated = steps['modify_existing_heat_recovery'][:result][:step_values]
                .find { |value| value[:name] == 'heat_exchangers_updated' }
      expect(updated[:value]).to eq(created.to_i)
      model = OpenStudio::Model::Model.load(File.join(output_path, 'baseline', 'in.osm')).get
      model.getHeatExchangerAirToAirSensibleAndLatents.each do |hx|
        expect(hx.latentEffectivenessat100HeatingAirFlow).to be_within(1e-6).of(0.61 * 0.9)
      end
      err = File.read(File.join(output_path, 'baseline', 'eplusout.err'))
      expect(err).not_to match(/\*\* (Severe|Fatal) /)
    end
  end
end
