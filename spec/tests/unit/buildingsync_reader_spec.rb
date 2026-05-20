
# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BuildingSync-gem/blob/develop/LICENSE.md
# *******************************************************************************
require 'tempfile'
require 'BOSS/buildingsync_reader/buildingsync_reader'

def wrap_in_site(xml)
  return """
    <auc:BuildingSync xmlns:auc='http://buildingsync.net/schemas/bedes-auc/2019'>
      <auc:Facilities>
        <auc:Facility>
          <auc:Sites>
            <auc:Site>
              #{xml}
            </auc:Site>
          </auc:Sites>
        </auc:Facility>
      </auc:Facilities>
    </auc:BuildingSync>
  """
end

RSpec.describe 'BuildingSyncReader' do
  describe 'get_climate_zone should' do
    it "get from site" do
      # Set Up
      doc = REXML::Document.new wrap_in_site(
          """
            <auc:ClimateZoneType>
              <auc:ASHRAE>
                <auc:ClimateZone>3C</auc:ClimateZone>
              </auc:ASHRAE>
              <auc:CaliforniaTitle24>
                <auc:ClimateZone>Climate Zone 3</auc:ClimateZone>
              </auc:CaliforniaTitle24>
            </auc:ClimateZoneType>
            <auc:Buildings>
              <auc:Building>
              </auc:Building>
            </auc:Buildings>
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
            <auc:Buildings>
              <auc:Building>
                <auc:ClimateZoneType>
                  <auc:ASHRAE>
                    <auc:ClimateZone>3C</auc:ClimateZone>
                  </auc:ASHRAE>
                  <auc:CaliforniaTitle24>
                    <auc:ClimateZone>Climate Zone 3</auc:ClimateZone>
                  </auc:CaliforniaTitle24>
                </auc:ClimateZoneType>
              </auc:Building>
            </auc:Buildings>
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
            <auc:Buildings>
              <auc:Building>
              </auc:Building>
            </auc:Buildings>
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
            <auc:Buildings>
              <auc:Building>
                <auc:Address>
                  <auc:City>San Francisco</auc:City>
                  <auc:State>CA</auc:State>
                </auc:Address>
              </auc:Building>
            </auc:Buildings>
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
          <auc:Buildings>
            <auc:Building>
              <auc:ClimateZoneType>
                <auc:ASHRAE>
                  <auc:ClimateZone>3C</auc:ClimateZone>
                </auc:ASHRAE>
              </auc:ClimateZoneType>
            </auc:Building>
          </auc:Buildings>
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
            <auc:Buildings>
              <auc:Building>
                <auc:Address>
                  <auc:City>San Francisco</auc:City>
                  <auc:State>CA</auc:State>
                </auc:Address>
              </auc:Building>
            </auc:Buildings>
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
            <auc:Address>
              <auc:City>San Francisco</auc:City>
              <auc:State>CA</auc:State>
            </auc:Address>
            <auc:Buildings>
              <auc:Building>
              </auc:Building>
            </auc:Buildings>
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
            <auc:Buildings>
              <auc:Building>
              </auc:Building>
            </auc:Buildings>
          """
        )

      # Action
      buidingsync_reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      city, state = buidingsync_reader.get_city_state

      # Assert
      expect([city, state]).to eq [nil, nil]
    end
  end
end
