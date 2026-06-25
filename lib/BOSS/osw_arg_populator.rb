# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'openstudio/extension'

class OSWArgPopulator
  def self.populate_set_run_period_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "set_run_period", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "set_run_period", key, value) }

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # -  timesteps_per_hour
    set_measure_argument.call("timesteps_per_hour", "4")
    # -  begin_date
    set_measure_argument.call("begin_date", "2019-01-01")
    # -  end_date
    set_measure_argument.call("end_date", "2019-12-31")
  end

  def self.populate_change_building_location_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "ChangeBuildingLocation", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "ChangeBuildingLocation", key, value) }

    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # -  weather_file_name
    set_measure_argument.call("weather_file_name", bsync_reader.get_epw_file_path)
    # -  climate_zone
    set_measure_argument.call("climate_zone", bsync_reader.get_climate_zone || "Lookup From Stat File")
  end

  def self.populate_create_bar_from_building_type_ratios_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "create_bar_from_building_type_ratios", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "create_bar_from_building_type_ratios", key, value) }

    building_type, bar_division_method = bsync_reader.get_building_type_and_bar_division_method

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # -  bldg_type_a
    set_measure_argument.call("bldg_type_a", building_type)
    # -  bldg_type_a_num_units
    # -  bldg_type_b
    # -  bldg_type_b_fract_bldg_area
    # -  bldg_type_b_num_units
    # -  bldg_type_c
    # -  bldg_type_c_fract_bldg_area
    # -  bldg_type_c_num_units
    # -  bldg_type_d
    # -  bldg_type_d_fract_bldg_area
    # -  bldg_type_d_num_units
    # -  total_bldg_floor_area
    set_measure_argument.call("total_bldg_floor_area", bsync_reader.get_total_floor_area)
    # -  floor_height -> FloorToFloorHeight, in total building section, else set to 0, smart default.
    set_measure_argument.call("floor_height", bsync_reader.get_floor_to_floor_height || 0)
    # -  num_stories_above_grade
    set_measure_argument.call("num_stories_above_grade", bsync_reader.get_floor_above_grade || 1)
    # -  num_stories_below_grade
    set_measure_argument.call("num_stories_below_grade", bsync_reader.get_floor_below_grade || 0)
    # -  building_rotation
    # -  template
    set_measure_argument.call("template", bsync_reader.get_standard_template)
    # -  ns_to_ew_ratio
    set_measure_argument.call("ns_to_ew_ratio", bsync_reader.get_aspect_ratio || 0)
    # -  wwr
    # -  party_wall_fraction
    # set_measure_argument.call("party_wall_fraction", building.party_wall_fraction.to_f)
    # -  story_multiplier_method
    set_measure_argument.call("story_multiplier_method", "None") # needed until os allows mutli basement
    # -  bar_division_method, as of right now, always use the default
    # set_measure_argument.call("bar_division_method", bar_division_method)
  end

  def self.populate_create_typical_building_from_model_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "create_typical_building_from_model", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "create_typical_building_from_model", key, value) }

    principal_HVAC_system_type = bsync_reader.get_principal_HVAC_system_type
    if principal_HVAC_system_type.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'BuildingSync.OSWARGPopulator.populate_create_typical_building_from_model_args',
        'No PrincipalHVACSystemType found in the BuildingSync XML. HVAC and SWH systems will be defaulted using the Inferred system type.')
    end

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # template
    set_measure_argument.call("template", bsync_reader.get_standard_template)
    # system_type
    set_measure_argument.call("system_type", principal_HVAC_system_type || "Inferred")
    # hvac_delivery_type
    # htg_src
    # clg_src
    # swh_src
    # kitchen_makeup
    # exterior_lighting_zone
    # add_constructions
    # wall_construction_type
    # add_space_type_loads
    # add_elevators
    # add_internal_mass
    # add_exterior_lights
    # onsite_parking_fraction
    # add_exhaust
    # add_swh
    set_measure_argument.call("add_swh", true)
    # add_thermostat
    # add_hvac
    set_measure_argument.call("add_hvac", true)
    # add_refrigeration
    # modify_wkdy_op_hrs
    # wkdy_op_hrs_start_time
    # wkdy_op_hrs_duration
    # modify_wknd_op_hrs
    # wknd_op_hrs_start_time
    # wknd_op_hrs_duration
    # unmet_hours_tolerance
    # remove_objects
    # use_upstream_args - set to false to prevent nested workflow creation
    set_measure_argument.call("use_upstream_args", false)
    # enable_dst
  end

  def self.populate_set_lighting_loads_by_LPD_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "SetLightingLoadsByLPD", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "SetLightingLoadsByLPD", key, value) }

    # skip if no total_installed_power or no usable floor area
    total_installed_power = bsync_reader.get_total_installed_power
    floor_area = bsync_reader.get_total_floor_area
    if total_installed_power.nil? || total_installed_power == 0 || floor_area.nil? || floor_area <= 0
      set_measure_argument.call("__SKIP__", true)
      return
    end

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # space_type "entire building"
    # lpd
    set_measure_argument.call("lpd", total_installed_power * 1000.0 / floor_area)
    # add_instance_all_spaces
    # material_cost
    # demolition_cost
    # years_until_costs_start
    # demo_cost_initial_const
    # expected_life
    # om_cost
    # om_frequency

  end

  def self.populate_set_electric_equipment_loads_by_epd_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "set_electric_equipment_loads_by_epd", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "set_electric_equipment_loads_by_epd", key, value) }

    # skip if no total_weighted_average_load
    total_weighted_average_load = bsync_reader.get_total_weighted_average_load
    if total_weighted_average_load.nil? or total_weighted_average_load == 0
      set_measure_argument.call("__SKIP__", true)
      return
    end

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # space_type "entire building"
    # epd
    set_measure_argument.call("epd", total_weighted_average_load / bsync_reader.get_total_floor_area)
    # add_instance_all_spaces
    # material_cost
    # demolition_cost
    # years_until_costs_start
    # demo_cost_initial_const
    # expected_life
    # om_cost
    # om_frequency
  end

  def self.populate_openstudio_results_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "openstudio_results", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "openstudio_results", key, value) }

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # -  reg_monthly_details - enable monthly fuel breakdown for results processing
    set_measure_argument.call("reg_monthly_details", true)
  end
end
