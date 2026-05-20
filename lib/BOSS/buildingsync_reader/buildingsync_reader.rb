require 'pry'

require 'openstudio-standards'

require 'boss/buildingsync_reader/bcl_weather_file_downloader'


module BOSS
  class BuildingSyncReader
    def initialize(bsync_doc, epw_file_path, standard_to_be_used)
      @bsync_doc = bsync_doc
      @epw_file_path = epw_file_path
      @standard_to_be_used = standard_to_be_used

      #  get namespace
      ns = @bsync_doc.elements[1].prefix
      @ns = ns.nil? || ns == ""? nil : ns + ":"

      # just some convenience attr
      @facility_xml = @bsync_doc.elements["/#{@ns}BuildingSync/#{@ns}Facilities/#{@ns}Facility"]
      @site_xml = @facility_xml.elements["#{@ns}Sites/#{@ns}Site"]
      @building_xml = @site_xml.elements["#{@ns}Buildings/#{@ns}Building"]

    end

    # use:
    #  1. given weather file
    #  2. city state from either building or site
    #  3. climate zone from either building ot site
    def get_epw_file_path
      if !@epw_file_path.nil?
        return @epw_file_path
      end

      city, state = get_city_state
      if !city.nil? && !state.nil?
        return BOSS::BCLWeatherFileDownloader.download_weather_file_from_city_name(city, state)
      end

      climate_zone = get_climate_zone
      if !climate_zone.nil?
        return OpenstudioStandards::Weather.climate_zone_representative_weather_file_path(climate_zone)
      end

      message = "Could not set a weather file as neither climate zone not city/state could be found"
      OpenStudio.logFree(OpenStudio::Error, 'BOSS.BuildingSyncReader.get_epw_file_path', message)
      raise StandardError, 'BOSS.BuildingSyncReader.get_epw_file_path ' + message
    end

    #  use:
    #  1. either building or cites climate of the type of the standard_to_be_used
    def get_climate_zone
      def _get_climate_zone(xml, type)
        return xml.elements["#{@ns}ClimateZoneType/#{@ns}#{type}/#{@ns}ClimateZone"]&.text
      end

      def _format_climate_zone(climate_zone, type)
        return "ASHRAE 169-2013-#{climate_zone}" if type == "ASHRAE"
        return "CEC T24-CEC#{climate_zone.gsub('Climate Zone', '').strip}" if type == "CaliforniaTitle24"
      end

      preferred_type = @standard_to_be_used == ASHRAE90_1 ? "ASHRAE" : "CaliforniaTitle24"

      climate_zone = _get_climate_zone(@building_xml, preferred_type)
      return _format_climate_zone(climate_zone, preferred_type) if !climate_zone.nil?

      climate_zone = _get_climate_zone(@site_xml, preferred_type)
      return _format_climate_zone(climate_zone, preferred_type) if !climate_zone.nil?
    end

    def get_city_state
      def _get_city_state(xml)
        return [
          xml.elements["#{@ns}Address/#{@ns}City"]&.text,
          xml.elements["#{@ns}Address/#{@ns}State"]&.text
        ]
      end

      city, state = _get_city_state(@building_xml)
      return city, state if !city.nil? && !state.nil?

      city, state = _get_city_state(@site_xml)
      return city, state if !city.nil? && !state.nil?
    end
  end
end
