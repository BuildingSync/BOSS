# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'json'
require 'openstudio-standards'
require_relative 'systems_map'
require_relative 'bcl_weather_file_downloader'
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

      BOSS.BOSS_logger.info("|\t|\t- checking for city state...")
      city, state = get_city_state
      if !city.nil? && !state.nil?
        BOSS.BOSS_logger.info("|\t|\t  city state: #{city}, #{state}")
        BOSS.BOSS_logger.info("|\t|\t- downloading weather file for #{city}, #{state}...")
        weather_file = BOSS::BCLWeatherFileDownloader.download_weather_file_from_city_name(city, state)
        BOSS.BOSS_logger.info("|\t|\t  downloaded")
        return weather_file
      else
        BOSS.BOSS_logger.info("|\t|\t  city state not found")
      end

      BOSS.BOSS_logger.info("|\t|\t- checking for climate zone...")
      climate_zone = get_climate_zone
      if !climate_zone.nil?
        BOSS.BOSS_logger.info("|\t|\t  climate zone: #{climate_zone}")
        BOSS.BOSS_logger.info("|\t|\t- downloading weather file for #{climate_zone}...")
        weather_file = OpenstudioStandards::Weather.climate_zone_representative_weather_file_path(climate_zone)
        BOSS.BOSS_logger.info("|\t|\t  downloaded")
        return weather_file
      else
        BOSS.BOSS_logger.info("|\t|\t  climate_zone not found")
      end

      message = "Could not set a weather file as neither climate zone not city/state could be found"
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

      BOSS.BOSS_logger.info("|\t|\t|\t- checking building climate zone...")
      climate_zone = _get_climate_zone(@building_xml, preferred_type)
      BOSS.BOSS_logger.info("|\t|\t|\t  climate zone: #{climate_zone}")
      return _format_climate_zone(climate_zone, preferred_type) if !climate_zone.nil?

      BOSS.BOSS_logger.info("|\t|\t|\t- checking site climate zone...")
      climate_zone = _get_climate_zone(@site_xml, preferred_type)
      BOSS.BOSS_logger.info("|\t|\t|\t  climate zone: #{climate_zone}")
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

      BOSS.BOSS_logger.info("|\t|\t|\t- checking building city state...")
      city, state = _get_city_state(@building_xml)
      BOSS.BOSS_logger.info("|\t|\t|\t  city state: #{city}, #{state}")
      return city, state if !city.nil? && !state.nil?

      BOSS.BOSS_logger.info("|\t|\t|\t- checking site city state...")
      city, state = _get_city_state(@site_xml)
      BOSS.BOSS_logger.info("|\t|\t|\t  city state: #{city}, #{state}")
      return city, state if !city.nil? && !state.nil?
    end

    # tries to get occupancy classification from:
    #  1. OccupancyClassification directly on the building
    #  2. OccupancyClassification of the building's sections: if only one section has it, use that one;
    #     if multiple sections have it, use the one attached to the largest floor area
    def get_occupancy_classification
      occupancy_classification = @building_xml.elements["#{@ns}OccupancyClassification"]&.text
      return occupancy_classification if !occupancy_classification.nil?

      section_elements = @building_xml.elements.each("#{@ns}Sections/#{@ns}Section"){|s| s}
      return nil if section_elements.nil?

      candidates = section_elements.filter_map do |section_element|
        section_occupancy_classification = section_element.elements["#{@ns}OccupancyClassification"]&.text
        next if section_occupancy_classification.nil?

        section_floor_areas_xml = section_element.elements["#{@ns}FloorAreas"]
        section_floor_area = !section_floor_areas_xml.nil? ? _get_total_floor_area_from_floor_areas_xml(section_floor_areas_xml) : 0
        {occupancy_classification: section_occupancy_classification, floor_area: section_floor_area}
      end
      return nil if candidates.empty?
      return candidates.first[:occupancy_classification] if candidates.length == 1

      return candidates.max_by { |candidate| candidate[:floor_area] }[:occupancy_classification]
    end

    # Use buildings OccupancyClassification, total_floor_area, and total_number_floors to find a openstudio mapping in building_types_by_occupancy_classification.json
    def get_building_type_and_bar_division_method
      BOSS.BOSS_logger.info("|\t|\t- gathering requirements of building type from file...")
      BOSS.BOSS_logger.info("|\t|\t|\t- getting occupancy classification...")
      occupancy_classification = get_occupancy_classification
      BOSS.BOSS_logger.info("|\t|\t|\t  occupancy classification: #{occupancy_classification}")
      BOSS.BOSS_logger.info("|\t|\t|\t- getting total floor area...")
      total_floor_area = get_total_floor_area(num_indent=4)
      BOSS.BOSS_logger.info("|\t|\t|\t  total_floor_area: #{total_floor_area}")
      BOSS.BOSS_logger.info("|\t|\t|\t- getting number of floors...")
      total_number_floors = _get_total_number_floors
      BOSS.BOSS_logger.info("|\t|\t|\t  total_number_floors: #{total_number_floors}")

      # get possible building_types based on occupancy_classification
      building_types_by_occupancy_classification = JSON.parse(
        File.read(BUILDING_TYPES_BY_OCCUPANCY_CLASSIFICATION_PATH),
        symbolize_names: true
      )
      building_types = building_types_by_occupancy_classification[occupancy_classification.to_sym] || []
      # find the one thats the right size
      BOSS.BOSS_logger.info("|\t|\t- finding building type and bar division method for occupancy_classification '#{occupancy_classification}', area of #{total_floor_area} sqft, #{total_number_floors} floors, standard '#{@standard_to_be_used}'...")
      building_types.each do |building_type|
        next if total_floor_area < (building_type[:min_floor_area]&.to_f || 0) # too small!
        next if total_floor_area > (building_type[:max_floor_area]&.to_f || Float::INFINITY) # too big!
        next if total_number_floors < (building_type[:min_number_floors]&.to_f || 0) # too small!
        next if total_number_floors > (building_type[:max_number_floors]&.to_f || Float::INFINITY) # too big!

        # just right!
        standards_building_type = building_type[:standards_building_type][:"#{@standard_to_be_used}"]
        bar_division_method = building_type[:bar_division_method]
        BOSS.BOSS_logger.info("|\t|\t  found building type '#{standards_building_type}', bar division method '#{bar_division_method}'")
        return standards_building_type, bar_division_method
      end
    end

    # tries to get total floor area from:
    #  1. /FloorAreas of building
    #  2. /FloorAreas of site
    def get_total_floor_area(num_indent=2)
      # check site floor area
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}- checking site for total floor area...")
      site_floor_areas_xml = @site_xml.elements["#{@ns}FloorAreas"]
      site_area = !site_floor_areas_xml.nil? ? _get_total_floor_area_from_floor_areas_xml(site_floor_areas_xml, num_indent+1) : 0
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}  site floor area is #{site_area}")
      return site_area if site_area > 0

      # check building floor area
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}- checking building for total floor area...")
      building_floor_areas_xml = @building_xml.elements["#{@ns}FloorAreas"]
      building_area = !building_floor_areas_xml.nil? ? _get_total_floor_area_from_floor_areas_xml(building_floor_areas_xml, num_indent+1) : 0
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}  building floor area is #{building_area}")
      return building_area if building_area > 0

      # TODO: read sections
    end

    # tries to get total floor area from:
    # measure expects floor area in ft2. XML floor area expected to be in ft2 as well (no conversion needed at this time)
    #  1. Gross floor area
    #  2. Sum of "Conditioned" + "Common" + "Heated and Cooled" + "Heated Only" + "Cooled Only" floor area
    #  3. Sum of "Conditioned above grade" + "Conditioned below grade" floor area
    def _get_total_floor_area_from_floor_areas_xml(floor_areas_xml, num_indent=5)
      # build a hash of the floor area in meters, by type
      floor_area_by_type = {}
      floor_area_by_type.default = 0

      floor_areas_xml.elements.each("#{@ns}FloorArea") do |floor_area_xml|
        floor_area_type = floor_area_xml.elements["#{@ns}FloorAreaType"].text
        floor_area = floor_area_xml.elements["#{@ns}FloorAreaValue"].text.to_f
        # puts "  #{floor_area_type} #{floor_area} #{OpenStudio.convert(floor_area, 'ft^2', 'm^2').get}"
        floor_area_by_type[floor_area_type] += floor_area
      end

      # first, try to get it from simply "Gross"
      BOSS.BOSS_logger.info("#{"|\t"*num_indent} - checking gross floor area")
      gross_floor_area = floor_area_by_type["Gross"]
      BOSS.BOSS_logger.info("#{"|\t"*num_indent} - gross floor area: #{gross_floor_area}")
      return gross_floor_area if gross_floor_area > 0

      # next, try to get it from "Conditioned" + "Common" + "Heated and Cooled" + "Heated Only" + "Cooled Only"
      BOSS.BOSS_logger.info("#{"|\t"*num_indent} - checking conditioned floor area")
      conditioned_area = floor_area_by_type["Conditioned"] + floor_area_by_type["Common"] + floor_area_by_type["Heated and Cooled"] + floor_area_by_type["Heated Only"] + floor_area_by_type["Cooled Only"]
      BOSS.BOSS_logger.info("#{"|\t"*num_indent} - conditioned floor area: #{conditioned_area}")
      return conditioned_area if conditioned_area > 0

      # next, try to get it from "Conditioned above grade" + "Conditioned below grade"
      BOSS.BOSS_logger.info("#{"|\t"*num_indent} - checking conditioned floor area (above + below)")
      conditioned_area = floor_area_by_type["Conditioned above grade"] + floor_area_by_type["Conditioned below grade"]
      BOSS.BOSS_logger.info("#{"|\t"*num_indent} - conditioned floor area (above + below): #{conditioned_area}")
      return conditioned_area if conditioned_area > 0

      # thats all we got!
      return 0
    end

    # tries to get total number floor from:
    #  1. building's FloorsAboveGrade
    #  2. building's ConditionedFloorsAboveGrade + UnconditionedFloorsAboveGrade
    def get_floor_above_grade(num_indent=2)
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}- checking building floors above grade...")
      floors_above_grade = @building_xml.elements["#{@ns}FloorsAboveGrade"]&.text
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}  floors above grade: #{floors_above_grade}")
      return floors_above_grade.to_f  if !floors_above_grade.nil?

      BOSS.BOSS_logger.info("#{"|\t"*num_indent}- checking building conditioned floors above grade and unconditioned floors above grade...")
      conditioned_floors_above_grade = @building_xml.elements["#{@ns}ConditionedFloorsAboveGrade"]&.text
      unconditioned_floors_above_grade = @building_xml.elements["#{@ns}UnconditionedFloorsAboveGrade"]&.text
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}  conditioned floors above grade: #{conditioned_floors_above_grade}")
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}  unconditioned floors above grade: #{unconditioned_floors_above_grade}")
      if !conditioned_floors_above_grade.nil? || !unconditioned_floors_above_grade.nil?
        return (conditioned_floors_above_grade.to_f || 0) + (unconditioned_floors_above_grade.to_f || 0)
      end

      BOSS.BOSS_logger.info("#{"|\t"*num_indent}- cannot find floors above grade")
      return nil
    end

    # tries to get total number floor from:
    #  1. building's FloorsBelowGrade
    #  2. building's ConditionedFloorsBelowGrade + UnconditionedFloorsBelowGrade
    def get_floor_below_grade(num_indent=2)
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}- checking building floors below grade...")
      floors_below_grade = @building_xml.elements["#{@ns}FloorsBelowGrade"]&.text
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}  floors below grade: #{floors_below_grade}")
      return floors_below_grade.to_f  if !floors_below_grade.nil?

      BOSS.BOSS_logger.info("#{"|\t"*num_indent}- checking building conditioned floors below grade and unconditioned floors below grade...")
      conditioned_floors_below_grade = @building_xml.elements["#{@ns}ConditionedFloorsBelowGrade"]&.text
      unconditioned_floors_below_grade = @building_xml.elements["#{@ns}UnconditionedFloorsBelowGrade"]&.text
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}  conditioned floors below grade: #{conditioned_floors_below_grade}")
      BOSS.BOSS_logger.info("#{"|\t"*num_indent}  unconditioned floors below grade: #{unconditioned_floors_below_grade}")
      if !conditioned_floors_below_grade.nil? || !unconditioned_floors_below_grade.nil?
        return (conditioned_floors_below_grade.to_f || 0) + (unconditioned_floors_below_grade.to_f || 0)
      end

      BOSS.BOSS_logger.info("#{"|\t"*num_indent}- cannot find floors below grade")
      return nil
    end

    def _get_total_number_floors
      BOSS.BOSS_logger.info("|\t|\t|\t|\t- getting floors above grade...")
      floors_above_grade = get_floor_above_grade(num_indent=5)
      BOSS.BOSS_logger.info("|\t|\t|\t|\t  floors above grade: #{floors_above_grade}")
      BOSS.BOSS_logger.info("|\t|\t|\t|\t- getting floors below grade...")
      floors_below_grade = get_floor_below_grade(num_indent=5)
      BOSS.BOSS_logger.info("|\t|\t|\t|\t  floors below grade: #{floors_below_grade}")

      return (floors_above_grade || 1) +  (floors_below_grade || 0)
    end


      # tries to get year built from:
    #  1. /YearOfLastMajorRemodel of building
    #  2. /YearOfConstruction of building
    def get_built_year
      BOSS.BOSS_logger.info("|\t|\t|\t|\t- checking year of major remodel...")
      year_of_major_remodel = @building_xml.elements["#{@ns}YearOfLastMajorRemodel"]&.text
      BOSS.BOSS_logger.info("|\t|\t|\t|\t  year of major remodel: #{year_of_major_remodel}...")
      return year_of_major_remodel.to_f if !year_of_major_remodel.nil?

      BOSS.BOSS_logger.info("|\t|\t|\t|\t- checking year of construction...")
      year_of_construction = @building_xml.elements["#{@ns}YearOfConstruction"]&.text
      BOSS.BOSS_logger.info("|\t|\t|\t|\t  year of construction: #{year_of_construction}...")
       return year_of_construction.to_f if !year_of_construction.nil?
    end

    #  map year built and standard_to_be_used to a standard_template
    def get_standard_template
      def _get_standard_template(built_year)
        if @standard_to_be_used == CA_TITLE24
          return "DEER Pre-1975" if built_year < 1975
          return "DEER 1985" if built_year >= 1975 && built_year < 1985
          return "DEER 1996" if built_year >= 1985 && built_year < 1996
          return "DEER 2003" if built_year >= 1996 && built_year < 2003
          return "DEER 2007" if built_year >= 2003 && built_year < 2007
          return "DEER 2011" if built_year >= 2007 && built_year < 2011
          return "DEER 2014" if built_year >= 2011 && built_year < 2014
          return "DEER 2015" if built_year >= 2014 && built_year < 2015
          return "DEER 2017" if built_year >= 2015 && built_year < 2017
          return "DEER 2020"

        elsif (@standard_to_be_used == ASHRAE90_1)
          return "DOE Ref Pre-1980" if built_year < 1980
          return "DOE Ref 1980-2004" if built_year >= 1980 && built_year < 2004
          return "90.1-2007" if built_year >= 2004 && built_year < 2007
          return "90.1-2010" if built_year >= 2007 && built_year < 2010
          return "90.1-2013" if built_year >= 2010 && built_year < 2013
          return "90.1-2016" if built_year >= 2013 && built_year < 2016
          return "90.1-2019"
        end
      end

      BOSS.BOSS_logger.info("|\t|\t- gathering requirements of template from file...")
      BOSS.BOSS_logger.info("|\t|\t|\t- getting year built...")
      built_year = get_built_year
      BOSS.BOSS_logger.info("|\t|\t|\t  year built: #{built_year}")
      BOSS.BOSS_logger.info("|\t|\t- finding template for building built in #{built_year}, standard #{@standard_to_be_used}...")
      template = _get_standard_template(built_year)
      BOSS.BOSS_logger.info("|\t|\t  template: #{template}")

      return template
    end

    def get_floor_to_floor_height
      BOSS.BOSS_logger.info("|\t|\t- checking the floor height of every section in building from file...")
      section_elements = @building_xml.elements.each("#{@ns}Sections/#{@ns}Section"){|s| s}
      return nil if section_elements.nil?
      floor_to_floor_heights = section_elements.map {|section_element| section_element.elements["#{@ns}FloorToFloorHeight"]&.text.to_f}
      BOSS.BOSS_logger.info("|\t|\t  section floor heights: #{floor_to_floor_heights}")

      return floor_to_floor_heights.first
    end

    def get_aspect_ratio
      aspect_ratio = @building_xml.elements["#{@ns}AspectRatio"]&.text
      return nil if aspect_ratio.nil?
      return aspect_ratio.to_f
    end

    # get principal hvac system type
    # @return [String]
    def get_principal_HVAC_system_type
      BOSS.BOSS_logger.info("|\t|\t- finding first hvac system with principal hvac system type...")
      # if no hvac systems, return nil
      hvac_systems = @facility_xml.elements.each("#{@ns}Systems/#{@ns}HVACSystems/#{@ns}HVACSystem") {|s| s}
      if hvac_systems.nil?
        BOSS.BOSS_logger.info("|\t|\t  no hvac systems found")
        return nil
      end

      # find first none nil principal_HVAC_system_type
      hvac_systems = hvac_systems.reject {|s| s.class == REXML::Comment}
      principal_HVAC_system_type = hvac_systems.map {|s| s.elements["#{@ns}PrincipalHVACSystemType/"]&.text}
      first_principal_HVAC_system_type = principal_HVAC_system_type.find {|x| !x.nil?}

      # if none, return nil, else return mapping
      if first_principal_HVAC_system_type.nil?
        BOSS.BOSS_logger.info("|\t|\t  no hvac systems principal hvac system type ")
        return nil
      end

      # map
      BOSS.BOSS_logger.info("|\t|\t  principal hvac system type: #{first_principal_HVAC_system_type}")
      BOSS.BOSS_logger.info("|\t|\t- mapping #{first_principal_HVAC_system_type} to measure arg options...")
      os_principal_HVAC_system_type = BuildingSyncToOSSystemMaps.get_hvac_map[first_principal_HVAC_system_type.to_s]
      BOSS.BOSS_logger.info("|\t|\t  os principal hvac system type: #{os_principal_HVAC_system_type}")

      return os_principal_HVAC_system_type
    end

    # get sum of /Systems/LightingSystems/LightingSystem/InstalledPower
    # @return [String]
    def get_total_installed_power
      # if no lighting systems, return nil
      BOSS.BOSS_logger.info("|\t|\t|\t- finding all lighting system installed power...")
      lighting_systems = @facility_xml.elements.each("#{@ns}Systems/#{@ns}LightingSystems/#{@ns}LightingSystem") {|s| s}
      if lighting_systems.nil?
        BOSS.BOSS_logger.info("|\t|\t|\t  no lighting systems found")
        return nil
      end

      # get all all_installed_powers
      lighting_systems = lighting_systems.reject {|s| s.class == REXML::Comment}
      all_installed_powers = lighting_systems.map {|s| s.elements["#{@ns}InstalledPower/"]&.first&.to_s&.to_f}
      BOSS.BOSS_logger.info("|\t|\t|\t  all lighting system installed power: #{all_installed_powers}")

      # if any nil, return nil, else return sum
      return nil if all_installed_powers.length == 0
      return nil if !all_installed_powers.all?
      return all_installed_powers.sum
    end

    # get sum of /Systems/LightingSystems/PlugLoads/WeightedAverageLoad
    # @return [String]
    def get_total_weighted_average_load
      # if no plug_loads, return nil
      BOSS.BOSS_logger.info("|\t|\t|\t- finding all plug load systems weighted average load...")
      plug_loads = @facility_xml.elements.each("#{@ns}Systems/#{@ns}PlugLoads/#{@ns}PlugLoad") {|s| s}
      if plug_loads.nil?
        BOSS.BOSS_logger.info("|\t|\t|\t  no plug load systems found")
        return nil
      end
      # get all weighted_average_loads
      plug_loads = plug_loads.reject {|s| s.class == REXML::Comment}
      all_weighted_average_loads = plug_loads.map {|s| s.elements["#{@ns}WeightedAverageLoad/"]&.text}
      BOSS.BOSS_logger.info("|\t|\t|\t  all plug load system weighted average load: #{all_weighted_average_loads}")

      # if any nil, return nil, else return sum
      return nil if all_weighted_average_loads.length == 0
      return nil if !all_weighted_average_loads.all?
      return all_weighted_average_loads.map {|s| s.to_f}.sum
    end

    # first valid window that has all mappable fields
    def get_window_data
      # if no windows, return nil
      fenestration_systems = @facility_xml.elements.each("#{@ns}Systems/#{@ns}FenestrationSystems/#{@ns}FenestrationSystem") {|s| s}
      return nil if fenestration_systems.nil?

      # get all windows
      windows = fenestration_systems.select {|fs| fs.elements["#{@ns}FenestrationType/#{@ns}Window"] }
      return nil if windows.empty?

      # iter through windows until we get one with all the required fields
      windows.each do |window|
        # get data
        fenestration_frame_material = window.elements["#{@ns}FenestrationFrameMaterial"]&.text
        glass_type = window.elements["#{@ns}GlassType"]&.text
        fenestration_glass_layers = window.elements["#{@ns}FenestrationGlassLayers"]&.text
        solar_heat_gain_coefficient = window.elements["#{@ns}SolarHeatGainCoefficient"]&.text
        visible_transmittance = window.elements["#{@ns}VisibleTransmittance"]&.text

        # We only need one of fenestration_u_factor/fenestration_r_value
        fenestration_u_factor = window.elements["#{@ns}FenestrationUFactor"]&.text
        if fenestration_u_factor.nil?
          fenestration_r_value = window.elements["#{@ns}FenestrationRValue"]&.text
          if !fenestration_r_value.nil? then fenestration_u_factor = (1.0 / fenestration_r_value.to_f).to_s end
        end

        # map data
        os_fenestration_frame_material = BuildingSyncToOSSystemMaps.get_frame_material_map[fenestration_frame_material.to_s]
        os_glass_type = BuildingSyncToOSSystemMaps.get_glass_type_map[glass_type.to_s]
        os_fenestration_glass_layers = BuildingSyncToOSSystemMaps.get_glass_layers_map[fenestration_glass_layers.to_s]

        # return if we can use this one
        if (
          !os_fenestration_frame_material.nil? &&
          !os_glass_type.nil? &&
          !os_fenestration_glass_layers.nil? &&
          !fenestration_u_factor.nil? &&
          !solar_heat_gain_coefficient.nil? &&
          !visible_transmittance.nil?
        )
          window_pane_type = [os_fenestration_glass_layers, os_glass_type, os_fenestration_frame_material].join(' - ')
          return window_pane_type, fenestration_u_factor, solar_heat_gain_coefficient, visible_transmittance
        end
      end
    return nil
  end
end
end
