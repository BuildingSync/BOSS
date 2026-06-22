# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'tempfile'
require 'BOSS/buildingsync_reader/buildingsync_reader'

def wrap_in_site(xml)
  return """
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
  """
end

RSpec.describe 'BuildingSyncReader' do
  describe 'get_climate_zone should' do
    it "get from site" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(
          """
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
          """
        )

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
      doc = REXML::Document.new wrap_in_site(
          """
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
          """
        )

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
      doc = REXML::Document.new wrap_in_site(
          """
            <Buildings>
              <Building>
              </Building>
            </Buildings>
          """
        )

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
      doc = REXML::Document.new wrap_in_site(
          """
            <Buildings>
              <Building>
                <Address>
                  <City>San Francisco</City>
                  <State>CA</State>
                </Address>
              </Building>
            </Buildings>
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      epw_file_path = buidingsync_reader.get_epw_file_path

      # Assert
      expect(File.basename(epw_file_path)).to eq "USA_CA_San.Francisco.Intl.AP.724940_TMY3.epw"
    end

    it "get from climate zone" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(
        """
          <Buildings>
            <Building>
              <ClimateZoneType>
                <ASHRAE>
                  <ClimateZone>3C</ClimateZone>
                </ASHRAE>
              </ClimateZoneType>
            </Building>
          </Buildings>
        """
      )

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
      doc = REXML::Document.new wrap_in_site(
          """
            <Buildings>
              <Building>
                <Address>
                  <City>San Francisco</City>
                  <State>CA</State>
                </Address>
              </Building>
            </Buildings>
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      city, state = buidingsync_reader.get_city_state

      # Assert
      expect([city, state]).to eq ["San Francisco", "CA"]
    end

    it "get from site" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(
          """
            <Address>
              <City>San Francisco</City>
              <State>CA</State>
            </Address>
            <Buildings>
              <Building>
              </Building>
            </Buildings>
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      city, state = buidingsync_reader.get_city_state

      # Assert
      expect([city, state]).to eq ["San Francisco", "CA"]
    end

    it "return nil" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(
          """
            <Buildings>
              <Building>
              </Building>
            </Buildings>
          """
        )

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
      return """
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
      """
    end

    it "sum InstalledPower" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(
          """
          <LightingSystems>
            <LightingSystem>
              <InstalledPower>2</InstalledPower>
            </LightingSystem>
            <LightingSystem>
              <InstalledPower>3</InstalledPower>
            </LightingSystem>
          </LightingSystems>
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_installed_power).to eq 5
    end

    it "return nil if any LightingSystem has nil InstalledPower" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(
          """
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
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_installed_power).to eq nil
    end

    it "return nil if no LightingSystems" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(
          """
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_installed_power).to eq nil
    end

    it "return nil if no InstalledPower" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(
          """
          <LightingSystems>
            <LightingSystem>
            </LightingSystem>
            <LightingSystem>
            </LightingSystem>
          </LightingSystems>
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_installed_power).to eq nil
    end
  end

  describe 'get_total_weighted_average_load should' do
    def wrap_in_systems(xml)
      return """
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
      """
    end

    it "sum weighted average load" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(
          """
          <PlugLoads>
            <PlugLoad>
              <WeightedAverageLoad>2</WeightedAverageLoad>
            </PlugLoad>
            <PlugLoad>
              <WeightedAverageLoad>3</WeightedAverageLoad>
            </PlugLoad>
          </PlugLoads>
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_weighted_average_load).to eq 5
    end

    it "return nil if any plugload has nil WeightedAverageLoad" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(
          """
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
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_weighted_average_load).to eq nil
    end

    it "return nil if no plug loads" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(
          """
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_weighted_average_load).to eq nil
    end

    it "return nil if no WeightedAverageLoad" do
      # Set Up
      doc = REXML::Document.new wrap_in_systems(
          """
          <PlugLoads>
            <PlugLoad>
            </PlugLoad>
            <PlugLoad>
            </PlugLoad>
          </PlugLoads>
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

      # Assert
      expect(buidingsync_reader.get_total_weighted_average_load).to eq nil
    end
  end
end
