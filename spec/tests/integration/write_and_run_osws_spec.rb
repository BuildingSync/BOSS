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
  end
end
