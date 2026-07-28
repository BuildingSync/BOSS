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

    def get_report_scenarios
      scenarios = []
      @facility_xml&.elements&.each("#{@ns}Reports/#{@ns}Report") do |report_xml|
        report_xml.elements.each("#{@ns}Scenarios/#{@ns}Scenario") do |scenario_xml|
          scenarios << _scenario_hash(report_xml, scenario_xml)
        end
      end

      return scenarios
    end

    def get_package_measure_scenarios
      return get_report_scenarios.select { |scenario| scenario[:scenario_type] == :package_of_measures }
    end

    def get_measures
      measures = {}
      _measure_xmls.each do |measure_xml|
        measure = _measure_hash(measure_xml)
        measures[measure[:measure_id]] = measure if !measure[:measure_id].nil?
      end

      return measures
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

    # Use buildings OccupancyClassification, total_floor_area, and total_number_floors to find a openstudio mapping in building_types_by_occupancy_classification.json
    def get_building_type_and_bar_division_method
      occupancy_classification = @building_xml.elements["#{@ns}OccupancyClassification"].text
      total_floor_area = get_total_floor_area
      total_number_floors = _get_total_number_floors

      # get possible building_types based on occupancy_classification
      building_types_by_occupancy_classification = JSON.parse(
        File.read(BUILDING_TYPES_BY_OCCUPANCY_CLASSIFICATION_PATH),
        symbolize_names: true
      )
      building_types = building_types_by_occupancy_classification[occupancy_classification.to_sym] || []
      # find the one thats the right size
      building_types.each do |building_type|
        next if total_floor_area < (building_type[:min_floor_area]&.to_f || 0) # too small!
        next if total_floor_area > (building_type[:max_floor_area]&.to_f || Float::INFINITY) # too big!
        next if total_number_floors < (building_type[:min_number_floors]&.to_f || 0) # too small!
        next if total_number_floors > (building_type[:max_number_floors]&.to_f || Float::INFINITY) # too big!

        return building_type[:standards_building_type][:"#{@standard_to_be_used}"], building_type[:bar_division_method] # just right!
      end
    end

    # tries to get total floor area from:
    #  1. /FloorAreas of building
    #  2. /FloorAreas of site
    def get_total_floor_area
      # check site floor area
      puts "++ site floor areas ++"
      site_floor_areas_xml = @site_xml.elements["#{@ns}FloorAreas"]
      site_area = !site_floor_areas_xml.nil? ? _get_total_floor_area_from_floor_areas_xml(site_floor_areas_xml) : 0
      return site_area if site_area > 0

      # check building floor area
      building_floor_areas_xml = @building_xml.elements["#{@ns}FloorAreas"]
        puts "++ building floor areas ++"
      building_area = !building_floor_areas_xml.nil? ? _get_total_floor_area_from_floor_areas_xml(building_floor_areas_xml) : 0
      return building_area if building_area > 0

      # TODO: read sections
    end

    # tries to get total floor area from:
    # measure expects floor area in ft2. XML floor area expected to be in ft2 as well (no conversion needed at this time)
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
        # puts "  #{floor_area_type} #{floor_area} #{OpenStudio.convert(floor_area, 'ft^2', 'm^2').get}"
        floor_area_by_type[floor_area_type] += floor_area
      end
      puts floor_area_by_type

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
    #  1. building's FloorsAboveGrade
    #  2. building's ConditionedFloorsAboveGrade + UnconditionedFloorsAboveGrade
    def get_floor_above_grade
      floors_above_grade = @building_xml.elements["#{@ns}FloorsAboveGrade"]&.text
      return floors_above_grade.to_f  if !floors_above_grade.nil?

      conditioned_floors_above_grade = @building_xml.elements["#{@ns}ConditionedFloorsAboveGrade"]&.text
      unconditioned_floors_above_grade = @building_xml.elements["#{@ns}UnconditionedFloorsAboveGrade"]&.text
      if !conditioned_floors_above_grade.nil? || !unconditioned_floors_above_grade.nil?
        return (conditioned_floors_above_grade.to_f || 0) + (unconditioned_floors_above_grade.to_f || 0)
      end

      return nil
    end

    # tries to get total number floor from:
    #  1. building's FloorsBelowGrade
    #  2. building's ConditionedFloorsBelowGrade + UnconditionedFloorsBelowGrade
    def get_floor_below_grade
      floors_below_grade = @building_xml.elements["#{@ns}FloorsBelowGrade"]&.text
      return floors_below_grade.to_f  if !floors_below_grade.nil?

      conditioned_floors_below_grade = @building_xml.elements["#{@ns}ConditionedFloorsBelowGrade"]&.text
      unconditioned_floors_below_grade = @building_xml.elements["#{@ns}UnconditionedFloorsBelowGrade"]&.text
      if !conditioned_floors_below_grade.nil? || !unconditioned_floors_below_grade.nil?
        return (conditioned_floors_below_grade.to_f || 0) + (unconditioned_floors_below_grade.to_f || 0)
      end

      return nil
    end

    def _get_total_number_floors
      floors_above_grade = get_floor_above_grade
      floors_below_grade = get_floor_below_grade

      return (floors_above_grade || 1) +  (floors_below_grade || 0)
    end


      # tries to get year built from:
    #  1. /YearOfLastMajorRemodel of building
    #  2. /YearOfConstruction of building
    def get_built_year
      year_of_major_remodel = @building_xml.elements["#{@ns}YearOfLastMajorRemodel"]&.text.to_f
      return year_of_major_remodel if !year_of_major_remodel.nil?

      year_of_construction = @building_xml.elements["#{@ns}YearOfConstruction"]&.text.to_f
      return year_of_construction if !year_of_construction.nil?
    end

    #  map year built and standard_to_be_used to a standard_template
    def get_standard_template
      built_year = get_built_year
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

    def get_floor_to_floor_height
      section_elements = @building_xml.elements.each("#{@ns}Sections/#{@ns}Section"){|s| s}
      return nil if section_elements.nil?
      floor_to_floor_heights = section_elements.map {|section_element| section_element.elements["#{@ns}FloorToFloorHeight"]&.text.to_f}

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
      # if no hvac systems, return nil
      hvac_systems = @facility_xml.elements.each("#{@ns}Systems/#{@ns}HVACSystems/#{@ns}HVACSystem") {|s| s}
      return nil if hvac_systems.nil?

      # find first none nil principal_HVAC_system_type
      hvac_systems = hvac_systems.reject {|s| s.class == REXML::Comment}
      principal_HVAC_system_type = hvac_systems.map {|s| s.elements["#{@ns}PrincipalHVACSystemType/"]&.text}
      first_principal_HVAC_system_type = principal_HVAC_system_type.find {|x| !x.nil?}

      # if none, return nil, else return mapping
      return nil if first_principal_HVAC_system_type.nil?
      return BuildingSyncToOSSystemMaps.get_hvac_map[first_principal_HVAC_system_type.to_s]
    end

    # get sum of /Systems/LightingSystems/LightingSystem/InstalledPower
    # @return [String]
    def get_total_installed_power
      # if no lighting systems, return nil
      lighting_systems = @facility_xml.elements.each("#{@ns}Systems/#{@ns}LightingSystems/#{@ns}LightingSystem") {|s| s}
      return nil if lighting_systems.nil?

      # get all all_installed_powers
      lighting_systems = lighting_systems.reject {|s| s.class == REXML::Comment}
      all_installed_powers = lighting_systems.map {|s| s.elements["#{@ns}InstalledPower/"]&.first&.to_s&.to_f}

      # if any nil, return nil, else return sum
      return nil if all_installed_powers.length == 0
      return nil if !all_installed_powers.all?
      return all_installed_powers.sum
    end

    # get sum of /Systems/LightingSystems/PlugLoads/WeightedAverageLoad
    # @return [String]
    def get_total_weighted_average_load
      # if no plug_loads, return nil
      plug_loads = @facility_xml.elements.each("#{@ns}Systems/#{@ns}PlugLoads/#{@ns}PlugLoad") {|s| s}
      return nil if plug_loads.nil?

      # get all weighted_average_loads
      plug_loads = plug_loads.reject {|s| s.class == REXML::Comment}
      all_weighted_average_loads = plug_loads.map {|s| s.elements["#{@ns}WeightedAverageLoad/"]&.text}


      # if any nil, return nil, else return sum
      return nil if all_weighted_average_loads.length == 0
      return nil if !all_weighted_average_loads.all?
      return all_weighted_average_loads.map {|s| s.to_f}.sum
    end

    private

    def _measure_xmls
      measure_xmls = []
      @facility_xml&.elements&.each("#{@ns}Measures/#{@ns}Measure") do |measure_xml|
        measure_xmls << measure_xml
      end

      return measure_xmls
    end

    def _measure_hash(measure_xml)
      technology_category_xml = _technology_category_xml(measure_xml)

      return {
        measure_id: measure_xml.attributes['ID'],
        system_category_affected: _element_text(measure_xml, "#{@ns}SystemCategoryAffected"),
        technology_category_element_name: _technology_category_element_name(technology_category_xml),
        measure_name: _technology_measure_name(technology_category_xml),
        custom_measure_name: _element_text(measure_xml, "#{@ns}CustomMeasureName"),
        linked_premises_idrefs: _linked_premises_idrefs(measure_xml),
        mv_cost: _numeric_element_text(measure_xml, "#{@ns}MVCost"),
        useful_life: _numeric_element_text(measure_xml, "#{@ns}UsefulLife"),
        measure_total_first_cost: _numeric_element_text(measure_xml, "#{@ns}MeasureTotalFirstCost"),
        measure_installation_cost: _numeric_element_text(measure_xml, "#{@ns}MeasureInstallationCost"),
        measure_material_cost: _numeric_element_text(measure_xml, "#{@ns}MeasureMaterialCost"),
        om_cost_annual_savings: _numeric_element_text(measure_xml, "#{@ns}MeasureSavingsAnalysis/#{@ns}OMCostAnnualSavings"),
        implementation_status: _element_text(measure_xml, "#{@ns}ImplementationStatus")
      }
    end

    def _technology_category_xml(measure_xml)
      technology_category_xml = measure_xml.elements["#{@ns}TechnologyCategories/#{@ns}TechnologyCategory"]

      return technology_category_xml&.elements&.[](1)
    end

    def _technology_category_element_name(technology_category_xml)
      return nil if technology_category_xml.nil?

      return technology_category_xml.name.to_s.split(':').last
    end

    def _technology_measure_name(technology_category_xml)
      return nil if technology_category_xml.nil?

      return _element_text(technology_category_xml, "#{@ns}MeasureName")
    end

    def _numeric_element_text(xml, path)
      value = _element_text(xml, path)
      return nil if value.nil? || value.strip.empty?

      return Float(value)
    rescue ArgumentError
      return nil
    end

    def _scenario_hash(report_xml, scenario_xml)
      package_xml = _package_of_measures_xml(scenario_xml)

      return {
        scenario_id: scenario_xml.attributes['ID'],
        scenario_name: _element_text(scenario_xml, "#{@ns}ScenarioName"),
        temporal_status: _element_text(scenario_xml, "#{@ns}TemporalStatus"),
        report_id: report_xml.attributes['ID'],
        scenario_type: _scenario_type(scenario_xml, package_xml),
        package_id: package_xml&.attributes&.[]('ID'),
        reference_case_id: package_xml&.elements&.[]("#{@ns}ReferenceCase")&.attributes&.[]('IDref'),
        measure_ids: _measure_idrefs(package_xml),
        linked_premises_idrefs: _linked_premises_idrefs(scenario_xml)
      }
    end

    def _scenario_type(scenario_xml, package_xml)
      return :package_of_measures if !package_xml.nil?

      current_building_xml = scenario_xml.elements["#{@ns}ScenarioType/#{@ns}CurrentBuilding"]
      return :current_building if !current_building_xml.nil?

      return :other
    end

    def _package_of_measures_xml(scenario_xml)
      return scenario_xml.elements["#{@ns}ScenarioType/#{@ns}PackageOfMeasures"]
    end

    def _element_text(xml, path)
      return xml.elements[path]&.text
    end

    def _measure_idrefs(package_xml)
      return [] if package_xml.nil?

      measure_ids = []
      package_xml.elements.each("#{@ns}MeasureIDs/#{@ns}MeasureID") do |measure_id_xml|
        measure_id = measure_id_xml.attributes['IDref']
        measure_ids << measure_id if !measure_id.nil?
      end
      return measure_ids
    end

    def _linked_premises_idrefs(xml)
      linked_premises_xml = xml.elements["#{@ns}LinkedPremises"]
      return [] if linked_premises_xml.nil?

      return _descendant_idrefs(linked_premises_xml)
    end

    def _descendant_idrefs(xml)
      idrefs = []
      xml.each_element do |child_xml|
        idref = child_xml.attributes['IDref']
        idrefs << idref if !idref.nil?
        idrefs.concat(_descendant_idrefs(child_xml))
      end

      return idrefs
    end
  end
end
