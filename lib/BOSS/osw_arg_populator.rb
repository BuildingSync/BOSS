# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'openstudio/extension'
require 'BOSS/boss_logger'

class OSWArgPopulator
  def self.populate_set_run_period_args(osw, bsync_reader)
    BOSS.BOSS_logger.info("+++++++++++++++++++++++++++ populating measure set_run_period +++++++++++++++++++++++")
    osw[:steps].append({"measure_dir_name": "set_run_period", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "set_run_period", key, value) }

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # -  timesteps_per_hour
    BOSS.BOSS_logger.info("|\t- setting arg 'timesteps_per_hour'...")
    BOSS.BOSS_logger.info("|\t  defaults to '4'")
    set_measure_argument.call("timesteps_per_hour", "4")
    # -  begin_date
    BOSS.BOSS_logger.info("|\t- setting arg 'begin_date'...")
    BOSS.BOSS_logger.info("|\t  defaults to '2019-01-01'")
    set_measure_argument.call("begin_date", "2019-01-01")
    # -  end_date
    BOSS.BOSS_logger.info("|\t- setting arg 'end_date'...")
    BOSS.BOSS_logger.info("|\t  defaults to '2019-12-31'")
    set_measure_argument.call("end_date", "2019-12-31")

    BOSS.BOSS_logger.info("++++++++++++++++++++++++++++++++++ populated. +++++++++++++++++++++++++++++++++++++++")
    BOSS.BOSS_logger.info("")
  end

  def self.populate_change_building_location_args(osw, bsync_reader)
    BOSS.BOSS_logger.info("+++++++++++++++++++++ populating measure ChangeBuildingLocation +++++++++++++++++++++")
    osw[:steps].append({"measure_dir_name": "ChangeBuildingLocation", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "ChangeBuildingLocation", key, value) }

    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # -  weather_file_name
    BOSS.BOSS_logger.info("|\t- setting arg 'weather_file_name'...")
    weather_file_name = bsync_reader.get_epw_file_path
    BOSS.BOSS_logger.info("|\t  set to #{weather_file_name}")
    set_measure_argument.call("weather_file_name", weather_file_name)
    # -  climate_zone
    BOSS.BOSS_logger.info("|\t- setting arg 'climate_zone'...")
    climate_zone = bsync_reader.get_climate_zone || "Lookup From Stat File"
    BOSS.BOSS_logger.info("|\t  set to #{climate_zone}")
    set_measure_argument.call("climate_zone", climate_zone)

    BOSS.BOSS_logger.info("++++++++++++++++++++++++++++++++++ populated. +++++++++++++++++++++++++++++++++++++++")
    BOSS.BOSS_logger.info("")
  end

  def self.populate_create_bar_from_building_type_ratios_args(osw, bsync_reader)
    BOSS.BOSS_logger.info("++++ populating measure create_bar_from_building_type_ratios ++++++++++++++")
    osw[:steps].append({"measure_dir_name": "create_bar_from_building_type_ratios", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "create_bar_from_building_type_ratios", key, value) }



    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # -  bldg_type_a
    BOSS.BOSS_logger.info("|\t- setting arg 'bldg_type_a'...")
    building_type, bar_division_method = bsync_reader.get_building_type_and_bar_division_method
    BOSS.BOSS_logger.info("|\t  set to #{building_type}")
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
    BOSS.BOSS_logger.info("|\t- setting arg 'total_bldg_floor_area'...")
    total_bldg_floor_area = bsync_reader.get_total_floor_area(num_indent=2)
    BOSS.BOSS_logger.info("|\t  set to #{total_bldg_floor_area}")
    set_measure_argument.call("total_bldg_floor_area", total_bldg_floor_area)
    # -  floor_height -> FloorToFloorHeight, in total building section, else set to 0, smart default.
    BOSS.BOSS_logger.info("|\t- setting arg 'floor_height'...")
    floor_height = bsync_reader.get_floor_to_floor_height || 0
    BOSS.BOSS_logger.info("|\t  set to #{floor_height}")
    set_measure_argument.call("floor_height", floor_height)
    # -  num_stories_above_grade
    BOSS.BOSS_logger.info("|\t- setting arg 'num_stories_above_grade'...")
    num_stories_above_grade = bsync_reader.get_floor_above_grade || 1
    BOSS.BOSS_logger.info("|\t  set to #{num_stories_above_grade}")
    set_measure_argument.call("num_stories_above_grade", num_stories_above_grade)
    # -  num_stories_below_grade
    BOSS.BOSS_logger.info("|\t- setting arg 'num_stories_below_grade'...")
    num_stories_below_grade = bsync_reader.get_floor_below_grade || 0
    BOSS.BOSS_logger.info("|\t  set to #{num_stories_below_grade}")
    set_measure_argument.call("num_stories_below_grade", num_stories_below_grade)
    # -  building_rotation
    # -  template
    BOSS.BOSS_logger.info("|\t- setting arg 'template'...")
    template = bsync_reader.get_standard_template
    BOSS.BOSS_logger.info("|\t  set to #{template}")
    set_measure_argument.call("template", template)
    # -  ns_to_ew_ratio
    BOSS.BOSS_logger.info("|\t- setting arg 'ns_to_ew_ratio'...")
    ns_to_ew_ratio = bsync_reader.get_aspect_ratio || 0
    BOSS.BOSS_logger.info("|\t  set to #{ns_to_ew_ratio}")
    set_measure_argument.call("ns_to_ew_ratio", ns_to_ew_ratio)
    # -  wwr
    # -  party_wall_fraction
    # set_measure_argument.call("party_wall_fraction", building.party_wall_fraction.to_f)
    # -  story_multiplier_method
    BOSS.BOSS_logger.info("|\t- setting arg 'story_multiplier_method'...")
    BOSS.BOSS_logger.info("|\t  defaults to 'None'")
    set_measure_argument.call("story_multiplier_method", "None") # needed until os allows mutli basement
    # -  bar_division_method, as of right now, always use the default
    # set_measure_argument.call("bar_division_method", bar_division_method)

    BOSS.BOSS_logger.info("++++++++++++++++++++++++++++++++++ populated. +++++++++++++++++++++++++++++++++++++++")
    BOSS.BOSS_logger.info("")
  end

  def self.populate_create_typical_building_from_model_args(osw, bsync_reader)
    BOSS.BOSS_logger.info("+++++ populating measure create_typical_building_from_model +++++++++++++++")
    osw[:steps].append({"measure_dir_name": "create_typical_building_from_model", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "create_typical_building_from_model", key, value) }

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # template
    BOSS.BOSS_logger.info("|\t- setting arg 'template'...")
    template = bsync_reader.get_standard_template
    BOSS.BOSS_logger.info("|\t  set to #{template}")
    set_measure_argument.call("template", template)
    # system_type
    BOSS.BOSS_logger.info("|\t- setting arg 'system_type'...")
    system_type = bsync_reader.get_principal_HVAC_system_type || "Inferred"
    BOSS.BOSS_logger.info("|\t  set to #{system_type}")
    set_measure_argument.call("system_type", system_type)
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
    BOSS.BOSS_logger.info("|\t- setting arg 'add_swh'...")
    BOSS.BOSS_logger.info("|\t  defaults to 'true'")
    set_measure_argument.call("add_swh", true)
    # add_thermostat
    # add_hvac
    BOSS.BOSS_logger.info("|\t- setting arg 'add_hvac'...")
    BOSS.BOSS_logger.info("|\t  defaults to 'true'")
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
    BOSS.BOSS_logger.info("|\t- setting arg 'use_upstream_args'...")
    BOSS.BOSS_logger.info("|\t  defaults to 'false'")
    set_measure_argument.call("use_upstream_args", false)
    # enable_dst

    BOSS.BOSS_logger.info("++++++++++++++++++++++++++++++++++ populated. +++++++++++++++++++++++++++++++++++++++")
    BOSS.BOSS_logger.info("")
  end

  def self.populate_set_lighting_loads_by_LPD_args(osw, bsync_reader)
    BOSS.BOSS_logger.info("++++++++++++++++++++++ populating measure SetLightingLoadsByLPD ++++++++++++++++++++")
    osw[:steps].append({"measure_dir_name": "SetLightingLoadsByLPD", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "SetLightingLoadsByLPD", key, value) }

    # skip if no total_installed_power or no usable floor area
    BOSS.BOSS_logger.info("|\t- gathering measure requirements...")
    BOSS.BOSS_logger.info("|\t|\t- getting total install power...")
    total_installed_power = bsync_reader.get_total_installed_power
    BOSS.BOSS_logger.info("|\t|\t  total install power: #{total_installed_power}")
    BOSS.BOSS_logger.info("|\t|\t- getting total floor area...")
    floor_area = bsync_reader.get_total_floor_area(num_indent=3)
    BOSS.BOSS_logger.info("|\t|\t  total floor area: #{floor_area}")
    if total_installed_power.nil? || total_installed_power == 0 || floor_area.nil? || floor_area <= 0
      BOSS.BOSS_logger.info("|\t  measure requirements unmet. Skippping.")
      BOSS.BOSS_logger.info("+++++++++++++++++++++++++++++++++++ skipped. ++++++++++++++++++++++++++++++++++++++++")
      BOSS.BOSS_logger.info("")
      set_measure_argument.call("__SKIP__", true)
      return
    end

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # space_type "entire building"
    # lpd
    BOSS.BOSS_logger.info("|\t- setting arg 'lpd'...")
    lpd = total_installed_power * 1000.0 / floor_area
    BOSS.BOSS_logger.info("|\t  set to #{lpd}")
    set_measure_argument.call("lpd", lpd)
    # add_instance_all_spaces
    # material_cost
    # demolition_cost
    # years_until_costs_start
    # demo_cost_initial_const
    # expected_life
    # om_cost
    # om_frequency
    BOSS.BOSS_logger.info("++++++++++++++++++++++++++++++++++ populated. +++++++++++++++++++++++++++++++++++++++")
    BOSS.BOSS_logger.info("")
  end

  def self.populate_set_electric_equipment_loads_by_epd_args(osw, bsync_reader)
    BOSS.BOSS_logger.info("+++++ populating measure set_electric_equipment_loads_by_epd ++++++++++++++")
    osw[:steps].append({"measure_dir_name": "set_electric_equipment_loads_by_epd", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "set_electric_equipment_loads_by_epd", key, value) }

    # skip if no total_weighted_average_load or no usable floor area
    BOSS.BOSS_logger.info("|\t- gathering measure requirements...")
    BOSS.BOSS_logger.info("|\t|\t- getting total weighted average load...")
    total_weighted_average_load = bsync_reader.get_total_weighted_average_load
    BOSS.BOSS_logger.info("|\t|\t  total weighted average load: #{total_weighted_average_load}")
    BOSS.BOSS_logger.info("|\t|\t- getting total floor area...")
    floor_area = bsync_reader.get_total_floor_area(num_indent=3)
    BOSS.BOSS_logger.info("|\t|\t  total floor area: #{floor_area}")
    if total_weighted_average_load.nil? || total_weighted_average_load == 0 || floor_area.nil? || floor_area <= 0
      BOSS.BOSS_logger.info("|\t  measure requirements unmet. Skippping.")
      BOSS.BOSS_logger.info("+++++++++++++++++++++++++++++++++++ skipped. ++++++++++++++++++++++++++++++++++++++++")
      BOSS.BOSS_logger.info("")
      set_measure_argument.call("__SKIP__", true)
      return
    end

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # space_type "entire building"
    # epd
    BOSS.BOSS_logger.info("|\t- setting arg 'epd'...")
    epd = total_weighted_average_load / floor_area
    BOSS.BOSS_logger.info("|\t  set to #{epd}")
    set_measure_argument.call("epd", epd)
    # material_cost
    # demolition_cost
    # years_until_costs_start
    # demo_cost_initial_const
    # expected_life
    # om_cost
    # om_frequency
    BOSS.BOSS_logger.info("++++++++++++++++++++++++++++++++++ populated. +++++++++++++++++++++++++++++++++++++++")
    BOSS.BOSS_logger.info("")
  end

  def self.populate_replace_baseline_windows_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "replace_baseline_windows", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "replace_baseline_windows", key, value) }

    # skip if no window_data
    window_data = bsync_reader.get_window_data
    if window_data.nil?
      set_measure_argument.call("__SKIP__", true)
      return
    end
    window_pane_type, fenestration_u_factor, solar_heat_gain_coefficient, visible_transmittance = window_data

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    set_measure_argument.call("window_pane_type", window_pane_type)
    set_measure_argument.call("u_value_ip", fenestration_u_factor)
    set_measure_argument.call("shgc", solar_heat_gain_coefficient)
    set_measure_argument.call("vlt", visible_transmittance)

  end

  def self.populate_openstudio_results_args(osw, bsync_reader)
    BOSS.BOSS_logger.info("+++++++++++++++++++++++++ populating measure openstudio_results +++++++++++++++++++++")
    osw[:steps].append({"measure_dir_name": "openstudio_results", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "openstudio_results", key, value) }

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # -  reg_monthly_details - enable monthly fuel breakdown for results processing
    BOSS.BOSS_logger.info("|\t- setting arg 'reg_monthly_details'...")
    BOSS.BOSS_logger.info("|\t  defaults to 'true'")
    set_measure_argument.call("reg_monthly_details", true)

    BOSS.BOSS_logger.info("++++++++++++++++++++++++++++++++++ populated. +++++++++++++++++++++++++++++++++++++++")
    BOSS.BOSS_logger.info("")
  end
end
