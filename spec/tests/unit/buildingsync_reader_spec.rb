# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'tempfile'
require 'json'
require 'BOSS/buildingsync_reader/buildingsync_reader'

UNIT_SPEC_FILES_DIR = File.expand_path('../../files', __dir__)

def load_fixture_doc(schema_version, file_name)
  xml_path = File.join(UNIT_SPEC_FILES_DIR, schema_version, file_name)
  REXML::Document.new(File.read(xml_path), ignore_whitespace_nodes: :all)
end

def load_fixture_json(schema_version, file_name)
  json_path = File.join(UNIT_SPEC_FILES_DIR, schema_version, file_name)
  JSON.parse(File.read(json_path))
end

def wrap_in_site(xml)
  <<~XML
    <BuildingSync>
      <Facilities>
        <Facility>
          <Sites>
            <Site>
              #{xml}
            </Site>
          </Sites>
        </Facility>
      </Facilities>
    </BuildingSync>
  XML
end

def wrap_in_facility(xml)
  <<~XML
    <BuildingSync>
      <Facilities>
        <Facility>
          <Sites>
            <Site>
              <Buildings>
                <Building>
                </Building>
              </Buildings>
            </Site>
          </Sites>
          #{xml}
        </Facility>
      </Facilities>
    </BuildingSync>
  XML
end

RSpec.describe 'BuildingSyncReader' do
  describe 'get_report_scenarios should' do
    it 'discover baseline and package scenarios from building_151' do
      # Set Up
      doc = load_fixture_doc('v2.7.0', 'building_151.xml')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      scenarios = buidingsync_reader.get_report_scenarios
      package_scenarios = buidingsync_reader.get_package_measure_scenarios

      # Assert
      expected_package_ids = [
        'Scenario1',
        'Scenario3',
        'Scenario4',
        'Scenario5',
        'Scenario6',
        'Scenario7',
        'Scenario8',
        'Scenario9',
        'Scenario10',
        'Scenario11',
        'Scenario12',
        'Scenario14',
        'Scenario16',
        'Scenario18',
        'Scenario24',
        'Scenario25'
      ]

      expect(scenarios.length).to eq 17
      expect(package_scenarios.map { |scenario| scenario[:scenario_id] }).to eq expected_package_ids
      expect(scenarios.count { |scenario| scenario[:scenario_type] == :current_building }).to eq 1
      expect(scenarios.count { |scenario| scenario[:scenario_type] == :package_of_measures }).to eq 16
    end

    it 'extract scenario fields from package and current-building scenarios' do
      # Set Up
      doc = load_fixture_doc('v2.7.0', 'building_151.xml')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      scenarios = buidingsync_reader.get_report_scenarios
      baseline = scenarios.find { |scenario| scenario[:scenario_id] == 'Baseline' }
      scenario1 = scenarios.find { |scenario| scenario[:scenario_id] == 'Scenario1' }

      # Assert
      expect(baseline).to include(
        scenario_id: 'Baseline',
        scenario_name: 'Baseline',
        scenario_type: :current_building,
        report_id: 'Report1',
        temporal_status: nil,
        package_id: nil,
        reference_case_id: nil,
        measure_ids: [],
        linked_premises_idrefs: []
      )

      expect(scenario1).to include(
        scenario_id: 'Scenario1',
        scenario_name: 'LED Only',
        scenario_type: :package_of_measures,
        report_id: 'Report1',
        temporal_status: nil,
        package_id: 'PackageOfMeasures1',
        reference_case_id: 'Baseline',
        measure_ids: ['Measure1'],
        linked_premises_idrefs: ['Building151']
      )
    end

    it 'extract temporal status and multiple measure IDrefs' do
      # Set Up
      doc = REXML::Document.new wrap_in_facility(<<~XML)
        <Reports>
          <Report ID="ReportA">
            <Scenarios>
              <Scenario ID="ScenarioA">
                <ScenarioName>Package A</ScenarioName>
                <TemporalStatus>Post retrofit</TemporalStatus>
                <ScenarioType>
                  <PackageOfMeasures ID="PackageA">
                    <ReferenceCase IDref="BaselineA"/>
                    <MeasureIDs>
                      <MeasureID IDref="MeasureA"/>
                      <MeasureID IDref="MeasureB"/>
                    </MeasureIDs>
                  </PackageOfMeasures>
                </ScenarioType>
              </Scenario>
            </Scenarios>
          </Report>
        </Reports>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      scenarios = buidingsync_reader.get_package_measure_scenarios

      # Assert
      expect(scenarios.first).to include(
        scenario_id: 'ScenarioA',
        temporal_status: 'Post retrofit',
        package_id: 'PackageA',
        reference_case_id: 'BaselineA',
        measure_ids: ['MeasureA', 'MeasureB']
      )
    end

    it 'uses the document namespace prefix when discovering scenarios' do
      # Set Up
      doc = load_fixture_doc('v2.7.0', 'building_151_n1.xml')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      scenarios = buidingsync_reader.get_report_scenarios

      # Assert
      expect(scenarios.find { |scenario| scenario[:scenario_id] == 'Baseline' }[:scenario_type]).to eq :current_building
      expect(buidingsync_reader.get_package_measure_scenarios.map { |scenario| scenario[:package_id] }).to include('PackageOfMeasures1')
    end

    it 'returns empty arrays when no report scenarios exist' do
      # Set Up
      doc = REXML::Document.new wrap_in_facility('')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_report_scenarios).to eq []
      expect(buidingsync_reader.get_package_measure_scenarios).to eq []
    end
  end

  describe 'get_measures should' do
    it 'index measures from building_151 by measure ID' do
      # Set Up
      doc = load_fixture_doc('v2.7.0', 'building_151.xml')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      measures = buidingsync_reader.get_measures

      # Assert
      expected_measure_ids = [
        'Measure1',
        'Measure3',
        'Measure4',
        'Measure5',
        'Measure6',
        'Measure7',
        'Measure8',
        'Measure9',
        'Measure10',
        'Measure11',
        'Measure12',
        'Measure14',
        'Measure16',
        'Measure18',
        'Measure24',
        'Measure25'
      ]

      expect(measures.keys).to eq expected_measure_ids
    end

    it 'extract measure category, name, linked premises, cost, savings, and status metadata' do
      # Set Up
      doc = load_fixture_doc('v2.7.0', 'building_151.xml')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      measure = buidingsync_reader.get_measures['Measure1']

      # Assert
      expect(measure).to include(
        measure_id: 'Measure1',
        system_category_affected: 'Lighting',
        technology_category_element_name: 'LightingImprovements',
        measure_name: 'Retrofit with light emitting diode technologies',
        custom_measure_name: 'TBD',
        linked_premises_idrefs: ['Building151'],
        mv_cost: 0.0,
        useful_life: 12.0,
        measure_total_first_cost: 267390.2,
        measure_installation_cost: 0.0,
        measure_material_cost: 0.0,
        om_cost_annual_savings: nil,
        implementation_status: 'Proposed'
      )
    end

    it 'resolves package MeasureID references against parsed measure metadata' do
      # Set Up
      fixture = File.join('spec', 'files', 'v2.7.0', 'building_151.xml')
      doc = load_fixture_doc('v2.7.0', 'building_151.xml')
      expected_output = load_fixture_json('v2.7.0', File.join('expected', 'building_151_scenario1_resolved_measures.json'))

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      measures = buidingsync_reader.get_measures
      scenario = buidingsync_reader.get_package_measure_scenarios.find { |package_scenario| package_scenario[:scenario_id] == 'Scenario1' }
      parsed_output = {
        fixture: fixture,
        measure_count: measures.length,
        scenario: scenario,
        resolved_measures: scenario[:measure_ids].map { |measure_id| measures[measure_id] }
      }

      # Assert
      expect(JSON.parse(JSON.generate(parsed_output))).to eq expected_output
    end

    it 'uses the document namespace prefix when indexing measures' do
      # Set Up
      doc = load_fixture_doc('v2.7.0', 'building_151_n1.xml')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      measure = buidingsync_reader.get_measures['Measure1']

      # Assert
      expect(measure).to include(
        technology_category_element_name: 'LightingImprovements',
        measure_name: 'Retrofit with light emitting diode technologies'
      )
    end

    it 'returns an empty hash when no measures exist' do
      # Set Up
      doc = load_fixture_doc('v2.7.0', 'building_151_no_measures.xml')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_measures).to eq({})
    end

    it 'extracts measure-owned savings metadata when present' do
      # Set Up
      doc = load_fixture_doc('v2.7.0', 'BuildingEQ-1.0.0.xml')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      measure = buidingsync_reader.get_measures['MeasureType-70023838998340']

      # Assert
      expect(measure).to include(
        measure_id: 'MeasureType-70023838998340',
        system_category_affected: 'Cooking',
        technology_category_element_name: 'FutureOtherECMs',
        measure_name: 'Other',
        linked_premises_idrefs: ['BuildingType-70023826271140'],
        useful_life: 50.0,
        measure_total_first_cost: 75242.0,
        om_cost_annual_savings: 260.0
      )
    end

    it 'keeps incomplete measure metadata nil-safe for later warning handling' do
      # Set Up
      doc = load_fixture_doc('v2.7.0', 'Golden Test File.xml')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      measure = buidingsync_reader.get_measures['Building1RemovePV']

      # Assert
      expect(measure).to include(
        measure_id: 'Building1RemovePV',
        system_category_affected: nil,
        technology_category_element_name: nil,
        measure_name: nil,
        custom_measure_name: nil,
        linked_premises_idrefs: ['Building1'],
        mv_cost: nil,
        useful_life: nil,
        measure_total_first_cost: nil,
        measure_installation_cost: nil,
        measure_material_cost: nil,
        om_cost_annual_savings: nil,
        implementation_status: nil
      )
    end
  end

  describe 'get_climate_zone should' do
    it "get from site" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(<<~XML)
        <ClimateZoneType>
          <ASHRAE>
            <ClimateZone>3C</ClimateZone>
          </ASHRAE>
          <CaliforniaTitle24>
            <ClimateZone>Climate Zone 3</ClimateZone>
          </CaliforniaTitle24>
        </ClimateZoneType>
        <Buildings>
          <Building>
          </Building>
        </Buildings>
      XML

      # Action
      ashrae_buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      ca_buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, CA_TITLE24)
      ashrae_climate_zone = ashrae_buidingsync_reader.get_climate_zone
      ca_climate_zone = ca_buidingsync_reader.get_climate_zone

      # Assert
      expect(ashrae_climate_zone).to eq "ASHRAE 169-2013-3C"
      expect(ca_climate_zone).to eq "CEC T24-CEC3"
    end

    it "get from building" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(<<~XML)
        <Buildings>
          <Building>
            <ClimateZoneType>
              <ASHRAE>
                <ClimateZone>3C</ClimateZone>
              </ASHRAE>
              <CaliforniaTitle24>
                <ClimateZone>Climate Zone 3</ClimateZone>
              </CaliforniaTitle24>
            </ClimateZoneType>
          </Building>
        </Buildings>
      XML

      # Action
      ashrae_buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      ca_buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, CA_TITLE24)
      ashrae_climate_zone = ashrae_buidingsync_reader.get_climate_zone
      ca_climate_zone = ca_buidingsync_reader.get_climate_zone

      # Assert
      expect(ashrae_climate_zone).to eq "ASHRAE 169-2013-3C"
      expect(ca_climate_zone).to eq "CEC T24-CEC3"
    end

    it "return nil" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(<<~XML)
        <Buildings>
          <Building>
          </Building>
        </Buildings>
      XML

      # Action
      ashrae_buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      ca_buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, CA_TITLE24)
      ashrae_climate_zone = ashrae_buidingsync_reader.get_climate_zone
      ca_climate_zone = ca_buidingsync_reader.get_climate_zone

      # Assert
      expect(ashrae_climate_zone).to eq nil
      expect(ca_climate_zone).to eq nil
    end
  end

  describe 'get_epw_file_path should' do
    it "get from city sate" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(<<~XML)
        <Buildings>
          <Building>
            <Address>
              <City>San Francisco</City>
              <State>CA</State>
            </Address>
          </Building>
        </Buildings>
      XML

      # Action
      allow(BOSS::BCLWeatherFileDownloader).to receive(:download_weather_file_from_city_name).with("San Francisco", "CA").and_return(openstudio_weather_file_path)
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      epw_file_path = buidingsync_reader.get_epw_file_path

      # Assert
      expect(File.basename(epw_file_path)).to eq "USA_CA_San.Francisco.Intl.AP.724940_TMY3.epw"
    end

    it "get from climate zone" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(<<~XML)
        <Buildings>
          <Building>
            <ClimateZoneType>
              <ASHRAE>
                <ClimateZone>3C</ClimateZone>
              </ASHRAE>
            </ClimateZoneType>
          </Building>
        </Buildings>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      epw_file_path = buidingsync_reader.get_epw_file_path

      # Assert
      expect(File.basename(epw_file_path)).to eq "USA_CA_San.Deigo-Brown.Field.Muni.AP.722904_TMY3.epw"
    end

    it "return nil" do
    end
  end

  describe 'get_city_state should' do
    it "get from building" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(<<~XML)
        <Buildings>
          <Building>
            <Address>
              <City>San Francisco</City>
              <State>CA</State>
            </Address>
          </Building>
        </Buildings>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      city, state = buidingsync_reader.get_city_state

      # Assert
      expect([city, state]).to eq ["San Francisco", "CA"]
    end

    it "get from site" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(<<~XML)
        <Address>
          <City>San Francisco</City>
          <State>CA</State>
        </Address>
        <Buildings>
          <Building>
          </Building>
        </Buildings>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      city, state = buidingsync_reader.get_city_state

      # Assert
      expect([city, state]).to eq ["San Francisco", "CA"]
    end

    it "return nil" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(<<~XML)
        <Buildings>
          <Building>
          </Building>
        </Buildings>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      city, state = buidingsync_reader.get_city_state

      # Assert
      expect([city, state]).to eq [nil, nil]
    end
  end

  describe 'get_building_type_and_bar_division_method should' do
  end

  describe 'get_total_floor_area should' do
  end

  describe 'get_floor_above_grade should' do
  end

  describe 'get_floor_below_grade should' do
  end

  describe 'get_floor_below_grade should' do
  end

  describe 'get_built_year should' do
  end

  describe 'get_standard_template should' do
  end

  describe 'get_floor_to_floor_height should' do
  end

  describe 'get_aspect_ratio should' do
  end

  describe 'get_principal_HVAC_system_type should' do
  end

  describe 'get_total_installed_power should' do
    def wrap_in_systems(xml)
      <<~XML
        <BuildingSync>
          <Facilities>
            <Facility>
              <Sites>
                <Site>
                </Site>
              </Sites>
              <Systems>
                #{xml}
              </Systems>
            </Facility>
          </Facilities>
        </BuildingSync>
      XML
    end

    it "sum InstalledPower" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(<<~XML)
        <LightingSystems>
          <LightingSystem>
            <InstalledPower>2</InstalledPower>
          </LightingSystem>
          <LightingSystem>
            <InstalledPower>3</InstalledPower>
          </LightingSystem>
        </LightingSystems>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_installed_power).to eq 5
    end

    it "return nil if any LightingSystem has nil InstalledPower" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(<<~XML)
        <LightingSystems>
          <LightingSystem>
            <InstalledPower>2</InstalledPower>
          </LightingSystem>
          <LightingSystem>
            <InstalledPower>3</InstalledPower>
          </LightingSystem>
          <LightingSystem>
          </LightingSystem>
        </LightingSystems>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_installed_power).to eq nil
    end

    it "return nil if no LightingSystems" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems('')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_installed_power).to eq nil
    end

    it "return nil if no InstalledPower" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(<<~XML)
        <LightingSystems>
          <LightingSystem>
          </LightingSystem>
          <LightingSystem>
          </LightingSystem>
        </LightingSystems>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_installed_power).to eq nil
    end
  end

  describe 'get_total_weighted_average_load should' do
    def wrap_in_systems(xml)
      <<~XML
        <BuildingSync>
          <Facilities>
            <Facility>
              <Sites>
                <Site>
                </Site>
              </Sites>
              <Systems>
                #{xml}
              </Systems>
            </Facility>
          </Facilities>
        </BuildingSync>
      XML
    end

    it "sum weighted average load" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(<<~XML)
        <PlugLoads>
          <PlugLoad>
            <WeightedAverageLoad>2</WeightedAverageLoad>
          </PlugLoad>
          <PlugLoad>
            <WeightedAverageLoad>3</WeightedAverageLoad>
          </PlugLoad>
        </PlugLoads>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_weighted_average_load).to eq 5
    end

    it "return nil if any plugload has nil WeightedAverageLoad" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(<<~XML)
        <PlugLoads>
          <PlugLoad>
            <WeightedAverageLoad>2</WeightedAverageLoad>
          </PlugLoad>
          <PlugLoad>
            <WeightedAverageLoad>3</WeightedAverageLoad>
          </PlugLoad>
          <PlugLoad>
          </PlugLoad>
        </PlugLoads>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_weighted_average_load).to eq nil
    end

    it "return nil if no plug loads" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems('')

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_weighted_average_load).to eq nil
    end

    it "return nil if no WeightedAverageLoad" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(<<~XML)
        <PlugLoads>
          <PlugLoad>
          </PlugLoad>
          <PlugLoad>
          </PlugLoad>
        </PlugLoads>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_weighted_average_load).to eq nil
    end
  end
end
