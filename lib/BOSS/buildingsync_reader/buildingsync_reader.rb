require 'pry'

require 'openstudio-standards'

require 'boss/buildingsync_reader/bcl_weather_file_downloader'
include Math

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

    # tries to get weather file from:
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

    # tries to get climate zone from:
    #  1. building climate of the type of the standard_to_be_used
    #  2. sites climate of the type of the standard_to_be_used
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

    # tries to get city state from:
    #  1. address of building
    #  2. address of site
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

    def get_building_type
      occupancy_classification = @building_xml.elements["#{@ns}OccupancyClassification"].text
      total_floor_area = get_total_floor_area
      total_number_floors = _get_total_number_floors

      # get possible building_types based on occupancy_classification
      building_types_by_occupancy_classification = eval(File.read(BUILDING_TYPES_BY_OCCUPANCY_CLASSIFICATION_PATH))
      building_types = building_types_by_occupancy_classification[:"#{occupancy_classification}"]

      # find the one thats the right size
      building_types.each do |building_type|
        next if total_floor_area < (building_type[:min_floor_area]&.to_f || 0) # too small!
        next if total_floor_area > (building_type[:max_floor_area]&.to_f || Float::INFINITY) # too big!
        next if total_number_floors < (building_type[:min_number_floors]&.to_f || 0) # too small!
        next if total_number_floors > (building_type[:max_number_floors]&.to_f || Float::INFINITY) # too big!

        return building_type[:standards_building_type][:"#{@standard_to_be_used}"] # just right!
      end
    end

    # tries to get total floor area from:
    #  1. /FloorAreas of building
    #  2. /FloorAreas of site
    def get_total_floor_area
      # check site floor area
      site_floor_areas_xml = @site_xml.elements["#{@ns}FloorAreas"]
      site_area = !site_floor_areas_xml.nil? ? _get_total_floor_area_from_floor_areas_xml(site_floor_areas_xml) : 0
      return site_area if site_area > 0

      # check building floor area
      building_floor_areas_xml = @building_xml.elements["#{@ns}FloorAreas"]
      building_area = !building_floor_areas_xml.nil? ? _get_total_floor_area_from_floor_areas_xml(building_floor_areas_xml) : 0
      return building_area if building_area > 0

      # TODO: read sections
    end

    # tries to get total floor area from:
    #  1. Gross floor area
    #  2. Sum of "Conditioned" + "Common" + "Heated and Cooled" + "Heated Only" + "Cooled Only" floor area
    #  3. Sum of "Conditioned above grade" + "Conditioned below grade" floor area
    def _get_total_floor_area_from_floor_areas_xml(floor_areas_xml)
      # build a hash of the floor area in meters, by type
      floor_area_by_type = {}
      floor_area_by_type.default = 0

      floor_areas_xml.elements.each("#{@ns}FloorArea") do |floor_area_xml|
        floor_area_type = floor_area_xml.elements["#{@ns}FloorAreaType"].text
        floor_area = floor_area_xml.elements["#{@ns}FloorAreaValue"].text.to_f
        floor_area_by_type[floor_area_type] += OpenStudio.convert(floor_area, 'ft^2', 'm^2').get
      end

      # first, try to get it from simply "Gross"
      gross_floor_area = floor_area_by_type["Gross"]
      return gross_floor_area if gross_floor_area > 0

      # next, try to get it from "Conditioned" + "Common" + "Heated and Cooled" + "Heated Only" + "Cooled Only"
      conditioned_area = floor_area_by_type["Conditioned"] + floor_area_by_type["Common"] + floor_area_by_type["Heated and Cooled"] + floor_area_by_type["Heated Only"] + floor_area_by_type["Cooled Only"]
      return conditioned_area if conditioned_area > 0

      # next, try to get it from "Conditioned above grade" + "Conditioned below grade"
      conditioned_area = floor_area_by_type["Conditioned above grade"] + floor_area_by_type["Conditioned below grade"]
      return conditioned_area if conditioned_area > 0

      # thats all we got!
      return 0
    end

    # tries to get total number floor from:
    #  1. building's FloorsAboveGrade + FloorsBelowGrade
    #  2. building's ConditionedFloorsAboveGrade + ConditionedFloorsBelowGrade + UnconditionedFloorsAboveGrade + UnconditionedFloorsBelowGrade
    def _get_total_number_floors
      floors_above_grade = @building_xml.elements["#{@ns}FloorsAboveGrade"]&.text.to_f
      floors_below_grade = @building_xml.elements["#{@ns}FloorsBelowGrade"]&.text.to_f
      if !floors_above_grade.nil? || !floors_below_grade.nil?
        return (floors_above_grade || 0) +  (floors_below_grade || 0)
      end

      conditioned_floors_above_grade = @building_xml.elements["#{@ns}ConditionedFloorsAboveGrade"]&.text.to_f
      conditioned_floors_below_grade = @building_xml.elements["#{@ns}ConditionedFloorsBelowGrade"]&.text.to_f
      unconditioned_floors_above_grade = @building_xml.elements["#{@ns}UnConditionedFloorsAboveGrade"]&.text.to_f
      unconditioned_floors_below_grade = @building_xml.elements["#{@ns}UnConditionedFloorsBelowGrade"]&.text.to_f
      if !conditioned_floors_above_grade.nil? || !conditioned_floors_below_grade.nil? || !unconditioned_floors_above_grade.nil? || !unconditioned_floors_below_grade.nil?
        return (conditioned_floors_above_grade || 0) +  (conditioned_floors_below_grade || 0) if !unconditioned_floors_above_grade.nil? || !unconditioned_floors_below_grade.nil?
      end
    end
  end
end
