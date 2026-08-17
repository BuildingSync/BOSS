# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'tempfile'
require 'BOSS/buildingsync_reader/buildingsync_reader'

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

RSpec.describe 'BuildingSyncReader' do
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

  describe 'get_window_data should' do
      good_window = <<~XML
        <FenestrationSystem ID='1' xmlns:auc=\"http://buildingsync.net/schemas/bedes-auc/2019\">
          <FenestrationType>
            <Window/>
          </FenestrationType>
          <FenestrationFrameMaterial>Aluminum no thermal break</FenestrationFrameMaterial>
          <FenestrationOperation>false</FenestrationOperation>
          <TightnessFitCondition>Average</TightnessFitCondition>
          <GlassType>Clear uncoated</GlassType>
          <FenestrationGlassLayers>Single pane</FenestrationGlassLayers>
          <SolarHeatGainCoefficient>0.391000</SolarHeatGainCoefficient>
          <VisibleTransmittance>0.391000</VisibleTransmittance>
          <FenestrationUFactor>3.241000</FenestrationUFactor>
        </FenestrationSystem>
      XML
      invalid_window = <<~XML
        <FenestrationSystem ID='2' xmlns:auc=\"http://buildingsync.net/schemas/bedes-auc/2019\">
          <FenestrationType>
            <Window/>
          </FenestrationType>
          <FenestrationFrameMaterial>Fiberglass</FenestrationFrameMaterial>
          <FenestrationOperation>false</FenestrationOperation>
          <TightnessFitCondition>Average</TightnessFitCondition>
          <GlassType>Clear uncoated</GlassType>
          <FenestrationGlassLayers>Single pane</FenestrationGlassLayers>
          <SolarHeatGainCoefficient>0.391000</SolarHeatGainCoefficient>
          <VisibleTransmittance>0.391000</VisibleTransmittance>
          <FenestrationUFactor>3.241000</FenestrationUFactor>
        </FenestrationSystem>
      XML
      door = <<~XML
        <FenestrationSystem ID=\"FenestrationSystemType-45021100\">
          <FenestrationType>
            <Door>
              <ExteriorDoorType>Uninsulated metal</ExteriorDoorType>
            </Door>
          </FenestrationType>
        </FenestrationSystem>
      XML

    it "work in happy case" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(<<~XML)
        <FenestrationSystems>
          #{good_window}
        </FenestrationSystems>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      window_pane_type, fenestration_u_factor, solar_heat_gain_coefficient, visible_transmittance = buidingsync_reader.get_window_data

      # Assertion
      expect(window_pane_type).to eq "Single - No LowE - Clear - Aluminum"
      expect(fenestration_u_factor).to eq "3.241000"
      expect(solar_heat_gain_coefficient).to eq "0.391000"
      expect(visible_transmittance).to eq "0.391000"
    end

    it "ignore doors and skylights" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(<<~XML)
        <FenestrationSystems>
          #{door}
          #{good_window}
        </FenestrationSystems>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      window_pane_type, fenestration_u_factor, solar_heat_gain_coefficient, visible_transmittance = buidingsync_reader.get_window_data

      # Assertion
      expect(window_pane_type).to eq "Single - No LowE - Clear - Aluminum"
      expect(fenestration_u_factor).to eq "3.241000"
      expect(solar_heat_gain_coefficient).to eq "0.391000"
      expect(visible_transmittance).to eq "0.391000"
    end

    it "work if first window is invalid but second isnt" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(<<~XML)
        <FenestrationSystems>
          #{invalid_window}
          #{good_window}
        </FenestrationSystems>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      window_pane_type, fenestration_u_factor, solar_heat_gain_coefficient, visible_transmittance = buidingsync_reader.get_window_data

      # Assertion
      expect(window_pane_type).to eq "Single - No LowE - Clear - Aluminum"
      expect(fenestration_u_factor).to eq "3.241000"
      expect(solar_heat_gain_coefficient).to eq "0.391000"
      expect(visible_transmittance).to eq "0.391000"
    end

    it "return nil if there are no windows" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems("")

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      window_pane_type, fenestration_u_factor, solar_heat_gain_coefficient, visible_transmittance = buidingsync_reader.get_window_data

      # Assertion
      expect(window_pane_type).to eq nil
    end

    # warn not error
    it "return nil if all windows are invalid" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(<<~XML)
        <FenestrationSystems>
          #{invalid_window}
        </FenestrationSystems>
      XML

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      window_pane_type, fenestration_u_factor, solar_heat_gain_coefficient, visible_transmittance = buidingsync_reader.get_window_data

      # Assertion
      expect(window_pane_type).to eq nil
    end
  end
end
