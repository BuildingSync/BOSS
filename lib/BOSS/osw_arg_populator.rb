# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BuildingSync-gem/blob/develop/LICENSE.md
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
    osw[:steps].append({"measure_dir_name": "change_building_location", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "change_building_location", key, value) }

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

    # Add args
    # -  __SKIP__
    set_measure_argument.call("__SKIP__", false)
    # -  bldg_type_a
    set_measure_argument.call("bldg_type_a", bsync_reader.get_building_type)
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
  end

  def self.populate_create_typical_building_from_model_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "create_typical_building_from_model", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "create_typical_building_from_model", key, value) }
  end

  def self.populate_set_lighting_loads_by_LPD_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "set_lighting_loads_by_LPD", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "set_lighting_loads_by_LPD", key, value) }
  end

  def self.populate_set_electric_equipment_loads_by_epd_args(osw, bsync_reader)
    osw[:steps].append({"measure_dir_name": "set_electric_equipment_loads_by_epd", "arguments": {}})
    set_measure_argument = lambda {| key, value | OpenStudio::Extension.set_measure_argument(osw, "set_electric_equipment_loads_by_epd", key, value) }
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
