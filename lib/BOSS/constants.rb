# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BuildingSync-gem/blob/develop/LICENSE.md
# *******************************************************************************

SCHEMA_2_0_URL = 'https://raw.githubusercontent.com/BuildingSync/schema/v2.0/BuildingSync.xsd'
SCHEMA_2_2_0_URL = 'https://raw.githubusercontent.com/BuildingSync/schema/v2.2.0/BuildingSync.xsd'
SCHEMA_2_4_0_URL = 'https://raw.githubusercontent.com/BuildingSync/schema/v2.4.0/BuildingSync.xsd'
SCHEMA_2_7_0_URL = 'https://raw.githubusercontent.com/BuildingSync/schema/v2.7.0/BuildingSync.xsd'
EMPTY_BASELINE_OSW_PATH = File.expand_path(File.join(__dir__, '/empty_baseline.osw'))
BUILDING_TYPES_BY_OCCUPANCY_CLASSIFICATION_PATH = File.expand_path(File.join(__dir__, 'buildingsync_reader/building_types_by_occupancy_classification.json'))

WEATHER_DIR = File.expand_path(File.join(__dir__, '../../weather'))


# Standards strings
ASHRAE90_1 = 'ASHRAE90.1'
CA_TITLE24 = 'CaliforniaTitle24'
