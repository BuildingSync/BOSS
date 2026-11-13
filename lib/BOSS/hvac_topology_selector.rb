# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'rexml/document'

module BOSS
  # Selects split HVAC topology measures from detailed BuildingSync HVACSystem data using
  # the predicates in buildingsync-measures-gem docs/HVAC_MAPPING_AND_MIGRATION.md.
  #
  # Every conditioning Delivery and every OtherHVACSystem yields exactly one Result, so no
  # constituent is dropped. Model zone resolution, call grouping, and quantity-vs-zone-count
  # guards need the model crosswalk and are left to later steps; results carry the
  # LinkedPremises references and a group_key for that work.
  class HvacTopologySelector
    STATUSES = [:match, :mapping_gap, :not_mappable, :missing_input, :conflicting_input, :no_hvac, :integrated].freeze

    # measure_arguments holds topology-measure arguments derived from the data (beyond operation,
    # zones, and template), e.g. { 'supplemental_heating_fuel' => 'NaturalGas' }.
    Result = Struct.new(:status, :configuration, :measure, :hvac_system_id, :record_ids, :premises,
                        :group_key, :messages, :measure_arguments, keyword_init: true)

    # Element accessors and predicates for one Delivery. Paths are '/'-separated local names,
    # so namespace prefixes do not matter.
    class Context
      attr_reader :sys, :d, :hs, :cs, :conflicts

      def initialize(sys, delivery, index)
        @sys = sys
        @d = delivery
        @index = index
        @conflicts = []
        @hs = resolve_one(delivery, 'HeatingSourceID', :heating_source)
        @cs = resolve_one(delivery, 'CoolingSourceID', :cooling_source)
      end

      def self.nodes(el, path)
        return [] if el.nil?

        path.split('/').reduce([el]) do |current, name|
          current.flat_map { |node| node.elements.to_a.select { |child| child.name == name } }
        end
      end

      def self.texts(el, path)
        nodes(el, path).map { |node| node.text.to_s.strip }
      end

      def nodes(el, path) = self.class.nodes(el, path)
      def node(el, path) = nodes(el, path).first
      def exists(el, path) = !nodes(el, path).empty?
      def absent(el, path) = nodes(el, path).empty?

      def eq(el, path, value)
        values = self.class.texts(el, path)
        !values.empty? && values.all? { |v| v == value }
      end

      def one_of(el, path, allowed)
        values = self.class.texts(el, path)
        !values.empty? && values.all? { |v| allowed.include?(v) }
      end

      # Guards are optional: they pass when the element is absent.
      def guard(el, path, allowed)
        values = self.class.texts(el, path)
        values.empty? || values.all? { |v| Array(allowed).include?(v) }
      end

      def quantity_guard(el, path)
        values = self.class.texts(el, path)
        values.empty? || values.all? { |v| Integer(v, exception: false) == 1 }
      end

      def ref_ids(el, path)
        nodes(el, path).map { |n| n.attributes['IDref'] }
      end

      # Exactly one reference resolving to a record of the given kind, else nil plus a conflict.
      def resolve_one(el, path, kind)
        ids = ref_ids(el, path)
        return nil if ids.empty?

        if ids.length > 1
          @conflicts << "#{el.attributes['ID'] || el.name}/#{path} has #{ids.length} references; expected one"
          return nil
        end
        record = @index.dig(kind, ids.first)
        @conflicts << "#{el.attributes['ID'] || el.name}/#{path} '#{ids.first}' does not resolve to a #{kind}" if record.nil?
        record
      end

      def hc = node(@sys, 'HeatingAndCoolingSystems')
      def z = node(@d, 'DeliveryType/ZoneEquipment')
      def a = node(@d, 'DeliveryType/CentralAirDistribution')
      def h = node(@hs, 'HeatingSourceType')
      def c = node(@cs, 'CoolingSourceType')
      def dx = node(c, 'DX')
      def fc = node(z, 'FanBased/FanBasedDistributionType/FanCoil')
      def mv(other) = node(other, 'OtherHVACType/MechanicalVentilation')

      def hp = memo(:hp) { h && resolve_one(h, 'SourceHeatingPlantID', :heating_plant) }
      def cp = memo(:cp) { c && resolve_one(c, 'CoolingPlantID', :cooling_plant) }
      def cn_dx = memo(:cn_dx) { dx && resolve_one(dx, 'CondenserPlantIDs/CondenserPlantID', :condenser_plant) }

      def cn_chiller
        memo(:cn_chiller) do
          chiller = node(cp, 'Chiller')
          chiller && resolve_one(chiller, 'CondenserPlantIDs/CondenserPlantID', :condenser_plant)
        end
      end

      # Resolves each reference once so a broken reference is reported once.
      def memo(key)
        @memo ||= {}
        @memo[key] = yield unless @memo.key?(key)
        @memo[key]
      end

      def cs_id = @cs&.attributes&.[]('ID')

      def heat_pump_shares_cs
        ids = ref_ids(h, 'HeatPump/CoolingSourceID')
        ids.length == 1 && !cs_id.nil? && ids.first == cs_id
      end

      def air_cooled_dx
        cn = cn_dx
        !cn.nil? && exists(cn, 'AirCooled') && absent(cn, 'AirCooled/EvaporativelyCooledCondenser')
      end

      # Packaged and terminal DX units are self-contained air-cooled units, so an omitted
      # condenser reference reads as air-cooled. VRF keeps the strict air_cooled_dx check.
      def packaged_air_cooled_dx
        absent(dx, 'CondenserPlantIDs') || air_cooled_dx
      end

      def gas_hot_water_plant
        eq(hs, 'HeatingMedium', 'Hot water') && !hp.nil? &&
          eq(hp, 'Boiler/BoilerType', 'Hot water') && eq(hp, 'PrimaryFuel', 'Natural gas')
      end

      def tower_chiller_plant
        eq(cs, 'CoolingMedium', 'Chilled water') && !cp.nil? &&
          eq(cp, 'Chiller/ChillerType', 'Vapor compression') &&
          eq(cp, 'Chiller/ChillerCompressorDriver', 'Electric Motor') && !cn_chiller.nil? &&
          eq(cn_chiller, 'WaterCooled/WaterCooledCondenserType', 'Cooling tower') &&
          absent(cn_chiller, 'WaterCooled/WaterSideEconomizer')
      end

      def single_zone_cav
        exists(@d, 'DeliveryType/CentralAirDistribution') && eq(a, 'AirDeliveryType', 'Central fan') &&
          eq(a, 'TerminalUnit', 'CAV terminal box no reheat') && eq(a, 'ReheatSource', 'None') &&
          eq(hc, 'ZoningSystemType', 'Single zone')
      end

      def multizone_vav(terminal, reheat)
        exists(@d, 'DeliveryType/CentralAirDistribution') && eq(a, 'AirDeliveryType', 'Central fan') &&
          eq(a, 'TerminalUnit', terminal) && eq(hc, 'ZoningSystemType', 'Multi zone') &&
          eq(a, 'ReheatSource', reheat)
      end

      # An empty FanBasedDistributionType (no child elements) counts as absent.
      def fan_based_distribution(el)
        nodes(el, 'FanBased/FanBasedDistributionType').any? { |n| !n.elements.to_a.empty? }
      end

      def gas_air_furnace
        exists(h, 'Furnace') && eq(hs, 'PrimaryFuel', 'Natural gas') && eq(hs, 'HeatingMedium', 'Air')
      end

      def zone_equipment_only
        !z.nil? && ['Convection', 'Radiant', 'Other'].all? { |n| absent(z, n) }
      end

      def plant_quantities_one(*plants)
        plants.compact.all? do |plant|
          quantity_guard(plant, 'Quantity') && ['Boiler', 'Chiller'].all? { |eq_name| quantity_guard(plant, "#{eq_name}/Quantity") }
        end
      end

      def conditioned
        ['ElectricResistance', 'Furnace', 'HeatPump', 'SourceHeatingPlantID'].any? { |n| exists(h, n) } ||
          ['DX', 'CoolingPlantID', 'EvaporativeCooler'].any? { |n| exists(c, n) }
      end
    end

    ELECTRIC = 'Electricity'
    AIR_REFRIGERANT = ['Air', 'Refrigerant'].freeze
    FURNACE_TYPES = ['Warm air', 'Other'].freeze
    # HeatPumpBackupSystemFuel => hvac_packaged_rooftop_heat_pump supplemental_heating_fuel
    BACKUP_FUELS = { 'Electricity' => 'Electricity', 'Natural gas' => 'NaturalGas' }.freeze

    # Exact rows and mapping-gap rows. :required, :absent, and :guards take a Context.
    # :absent and :guards return descriptions of failed checks.
    DELIVERY_RULES = [
      {
        configuration: 'Packaged Terminal Air Conditioner', measure: 'hvac_ptac', status: :match, group: :delivery,
        required: lambda { |x|
          x.zone_equipment_only && x.exists(x.h, 'ElectricResistance') &&
            x.eq(x.dx, 'DXSystemType', 'Packaged terminal air conditioner (PTAC)') && x.packaged_air_cooled_dx
        },
        absent: ->(x) { x.fan_based_distribution(x.z) ? ['Z/FanBased/FanBasedDistributionType'] : [] },
        guards: lambda { |x|
          [
            ['HS/PrimaryFuel', x.guard(x.hs, 'PrimaryFuel', ELECTRIC)],
            ['CS/PrimaryFuel', x.guard(x.cs, 'PrimaryFuel', ELECTRIC)],
            ['HS/HeatingMedium', x.guard(x.hs, 'HeatingMedium', 'Air')],
            ['CS/CoolingMedium', x.guard(x.cs, 'CoolingMedium', AIR_REFRIGERANT)]
          ]
        }
      },
      {
        configuration: 'Four Pipe Fan Coil Unit', measure: 'hvac_four_pipe_fan_coil', status: :match, group: :plants,
        required: lambda { |x|
          x.zone_equipment_only && x.eq(x.fc, 'FanCoilType', 'Fan coil 4 pipe') &&
            x.gas_hot_water_plant && x.tower_chiller_plant
        },
        absent: ->(_x) { [] },
        guards: lambda { |x|
          [
            ['FC/HVACPipeConfiguration', x.guard(x.fc, 'HVACPipeConfiguration', '4 pipe')],
            ['HS/PrimaryFuel', x.guard(x.hs, 'PrimaryFuel', 'Natural gas')],
            ['CS/PrimaryFuel', x.guard(x.cs, 'PrimaryFuel', ELECTRIC)],
            ['CP/PrimaryFuel', x.guard(x.cp, 'PrimaryFuel', ELECTRIC)],
            ['CP/CondenserType', x.guard(x.cp, 'CondenserType', 'Water Cooled')],
            ['plant quantities', x.plant_quantities_one(x.hp, x.cp, x.cn_chiller)]
          ]
        }
      },
      {
        configuration: 'Packaged Terminal Heat Pump', measure: 'hvac_pthp', status: :match, group: :delivery,
        required: lambda { |x|
          x.zone_equipment_only && x.eq(x.h, 'HeatPump/HeatPumpType', 'Packaged Terminal') && x.heat_pump_shares_cs &&
            x.eq(x.h, 'HeatPump/HeatPumpBackupSystemFuel', ELECTRIC) && x.absent(x.h, 'HeatPump/LinkedHeatingPlantID') &&
            x.eq(x.dx, 'DXSystemType', 'Packaged terminal heat pump (PTHP)') && x.packaged_air_cooled_dx
        },
        absent: ->(x) { x.fan_based_distribution(x.z) ? ['Z/FanBased/FanBasedDistributionType'] : [] },
        guards: lambda { |x|
          [
            ['HS/PrimaryFuel', x.guard(x.hs, 'PrimaryFuel', ELECTRIC)],
            ['CS/PrimaryFuel', x.guard(x.cs, 'PrimaryFuel', ELECTRIC)],
            ['HS/HeatingMedium', x.guard(x.hs, 'HeatingMedium', AIR_REFRIGERANT)],
            ['CS/CoolingMedium', x.guard(x.cs, 'CoolingMedium', AIR_REFRIGERANT)]
          ]
        }
      },
      {
        configuration: 'Packaged Rooftop Air Conditioner', measure: 'hvac_packaged_rooftop_ac', status: :match, group: :delivery,
        required: lambda { |x|
          x.single_zone_cav && x.gas_air_furnace &&
            x.eq(x.dx, 'DXSystemType', 'Packaged/unitary direct expansion/RTU') && x.packaged_air_cooled_dx
        },
        absent: ->(x) { central_air_absent(x) },
        guards: lambda { |x|
          [
            ['H/Furnace/FurnaceType', x.guard(x.h, 'Furnace/FurnaceType', FURNACE_TYPES)],
            ['CS/PrimaryFuel', x.guard(x.cs, 'PrimaryFuel', ELECTRIC)],
            ['CS/CoolingMedium', x.guard(x.cs, 'CoolingMedium', AIR_REFRIGERANT)]
          ]
        }
      },
      {
        configuration: 'Packaged Rooftop Heat Pump', measure: 'hvac_packaged_rooftop_heat_pump', status: :match, group: :delivery,
        required: lambda { |x|
          x.single_zone_cav && x.eq(x.h, 'HeatPump/HeatPumpType', 'Packaged Unitary') && x.heat_pump_shares_cs &&
            x.one_of(x.h, 'HeatPump/HeatPumpBackupSystemFuel', BACKUP_FUELS.keys) &&
            x.absent(x.h, 'HeatPump/LinkedHeatingPlantID') &&
            x.eq(x.dx, 'DXSystemType', 'Packaged/unitary heat pump') && x.packaged_air_cooled_dx
        },
        arguments: lambda { |x|
          { 'supplemental_heating_fuel' => BACKUP_FUELS[x.class.texts(x.h, 'HeatPump/HeatPumpBackupSystemFuel').first] }
        },
        absent: ->(x) { central_air_absent(x) },
        guards: lambda { |x|
          [
            ['HS/PrimaryFuel', x.guard(x.hs, 'PrimaryFuel', ELECTRIC)],
            ['CS/PrimaryFuel', x.guard(x.cs, 'PrimaryFuel', ELECTRIC)],
            ['HS/HeatingMedium', x.guard(x.hs, 'HeatingMedium', AIR_REFRIGERANT)],
            ['CS/CoolingMedium', x.guard(x.cs, 'CoolingMedium', AIR_REFRIGERANT)]
          ]
        }
      },
      {
        configuration: 'Packaged Rooftop VAV with Hot Water Reheat', measure: 'hvac_packaged_rooftop_vav_hw_reheat',
        status: :match, group: :cooling_source,
        required: lambda { |x|
          x.multizone_vav('VAV terminal box not fan powered with reheat', 'Heating plant') && x.gas_hot_water_plant &&
            x.ref_ids(x.a, 'ReheatPlantID') == [x.hp.attributes['ID']] &&
            x.eq(x.dx, 'DXSystemType', 'Packaged/unitary direct expansion/RTU') && x.packaged_air_cooled_dx
        },
        absent: ->(x) { x.fan_based_distribution(x.a) ? ['A/FanBased/FanBasedDistributionType'] : [] },
        guards: lambda { |x|
          [
            ['HS/PrimaryFuel', x.guard(x.hs, 'PrimaryFuel', 'Natural gas')],
            ['CS/PrimaryFuel', x.guard(x.cs, 'PrimaryFuel', ELECTRIC)],
            ['CS/CoolingMedium', x.guard(x.cs, 'CoolingMedium', AIR_REFRIGERANT)],
            ['CS/Quantity', x.quantity_guard(x.cs, 'Quantity')],
            ['plant quantities', x.plant_quantities_one(x.hp)]
          ]
        }
      },
      {
        configuration: 'Packaged Rooftop VAV with Electric Reheat', measure: 'hvac_packaged_rooftop_vav_electric_reheat',
        status: :mapping_gap, group: :cooling_source,
        gap: 'The terminal enum combines parallel and series fan-powered boxes; the measure builds only parallel boxes.',
        required: lambda { |x|
          x.multizone_vav('VAV terminal box fan powered with reheat', 'Local electric resistance') &&
            x.exists(x.h, 'ElectricResistance') &&
            x.eq(x.dx, 'DXSystemType', 'Packaged/unitary direct expansion/RTU') && x.packaged_air_cooled_dx
        }
      },
      {
        configuration: 'VAV with Hot Water Reheat', measure: 'hvac_vav_hw_reheat', status: :match, group: :cooling_source,
        required: lambda { |x|
          x.multizone_vav('VAV terminal box not fan powered with reheat', 'Heating plant') && x.gas_hot_water_plant &&
            x.ref_ids(x.a, 'ReheatPlantID') == [x.hp.attributes['ID']] && x.tower_chiller_plant
        },
        absent: ->(x) { x.fan_based_distribution(x.a) ? ['A/FanBased/FanBasedDistributionType'] : [] },
        guards: lambda { |x|
          [
            ['HS/PrimaryFuel', x.guard(x.hs, 'PrimaryFuel', 'Natural gas')],
            ['CS/PrimaryFuel', x.guard(x.cs, 'PrimaryFuel', ELECTRIC)],
            ['CS/Quantity', x.quantity_guard(x.cs, 'Quantity')],
            ['CP/PrimaryFuel', x.guard(x.cp, 'PrimaryFuel', ELECTRIC)],
            ['CP/CondenserType', x.guard(x.cp, 'CondenserType', 'Water Cooled')],
            ['plant quantities', x.plant_quantities_one(x.hp, x.cp, x.cn_chiller)]
          ]
        }
      },
      {
        configuration: 'VAV with Electric Reheat', measure: 'hvac_vav_electric_reheat', status: :mapping_gap, group: :cooling_source,
        gap: 'The terminal enum combines parallel and series fan-powered boxes; the measure builds only parallel boxes.',
        required: lambda { |x|
          x.multizone_vav('VAV terminal box fan powered with reheat', 'Local electric resistance') &&
            x.exists(x.h, 'ElectricResistance') && x.tower_chiller_plant
        }
      },
      {
        configuration: 'Warm Air Furnace', measure: 'hvac_warm_air_furnace', status: :match, group: :delivery,
        required: lambda { |x|
          x.single_zone_cav && x.gas_air_furnace && x.exists(x.c, 'NoCooling')
        },
        absent: ->(x) { central_air_absent(x) },
        guards: ->(x) { [['H/Furnace/FurnaceType', x.guard(x.h, 'Furnace/FurnaceType', FURNACE_TYPES)]] }
      },
      {
        configuration: 'Water Loop Heat Pump', measure: 'hvac_water_loop_heat_pump', status: :mapping_gap, group: :delivery,
        gap: 'BuildingSync does not uniquely encode the generated terminal, shared loop, and fluid-cooler arrangement.',
        required: lambda { |x|
          !x.z.nil? && x.exists(x.h, 'HeatPump') && x.heat_pump_shares_cs && !x.dx.nil? &&
            !x.cn_dx.nil? && x.exists(x.cn_dx, 'WaterCooled')
        }
      },
      {
        configuration: 'Ground Source Heat Pump', measure: 'hvac_ground_source_heat_pump', status: :mapping_gap, group: :delivery,
        gap: 'The measure approximates the ground loop and creates no well or borefield geometry.',
        required: lambda { |x|
          !x.z.nil? && x.exists(x.h, 'HeatPump') && x.heat_pump_shares_cs && !x.cn_dx.nil? &&
            x.exists(x.cn_dx, 'GroundSource')
        }
      },
      {
        configuration: 'VRF Terminal Unit', measure: 'hvac_vrf', status: :match, group: :cooling_source,
        required: lambda { |x|
          x.zone_equipment_only && x.eq(x.fc, 'FanCoilType', 'VRF terminal units') && x.exists(x.h, 'HeatPump') &&
            x.heat_pump_shares_cs && x.absent(x.h, 'HeatPump/LinkedHeatingPlantID') &&
            x.absent(x.h, 'HeatPump/HeatPumpBackupSystemFuel') &&
            x.eq(x.dx, 'DXSystemType', 'Variable refrigerant flow') && x.air_cooled_dx
        },
        absent: ->(x) { x.exists(x.fc, 'HVACPipeConfiguration') ? ['FC/HVACPipeConfiguration'] : [] },
        guards: lambda { |x|
          [
            ['HS/PrimaryFuel', x.guard(x.hs, 'PrimaryFuel', ELECTRIC)],
            ['CS/PrimaryFuel', x.guard(x.cs, 'PrimaryFuel', ELECTRIC)],
            ['HS/HeatingMedium', x.guard(x.hs, 'HeatingMedium', AIR_REFRIGERANT)],
            ['CS/CoolingMedium', x.guard(x.cs, 'CoolingMedium', AIR_REFRIGERANT)],
            ['CS/Quantity', x.quantity_guard(x.cs, 'Quantity')]
          ]
        }
      },
      {
        configuration: 'Chilled Beam', measure: 'hvac_chilled_beam', status: :mapping_gap, group: :plants,
        gap: 'BuildingSync has no active/passive or beam pipe-arrangement selector; the measure builds active four-pipe beams.',
        required: lambda { |x|
          x.eq(x.z, 'Convection/ConvectionType', 'Chilled beam') && x.gas_hot_water_plant && x.tower_chiller_plant
        }
      },
      {
        configuration: 'Hydronic radiant floor / ceiling', measure: 'hvac_radiant', status: :mapping_gap, group: :plants,
        gap: 'BuildingSync combines floor and ceiling radiant; the measure builds floors only.',
        required: lambda { |x|
          x.eq(x.z, 'Radiant/RadiantType', 'Radiant floor or ceiling') && x.gas_hot_water_plant && x.tower_chiller_plant
        }
      }
    ].freeze

    # Configurations the gem cannot generate. Each takes a Context and returns true on a hit.
    NOT_MAPPABLE_DELIVERY = [
      ['Split DX air conditioner', ->(x) { x.eq(x.dx, 'DXSystemType', 'Split DX air conditioner') }],
      ['Split / mini-split / multi-split heat pump', lambda { |x|
        x.eq(x.dx, 'DXSystemType', 'Split heat pump') || x.one_of(x.fc, 'FanCoilType', ['Mini-split', 'Multi-split'])
      }],
      ['Single-package vertical AC / heat pump', lambda { |x|
        x.one_of(x.dx, 'DXSystemType', ['Single package vertical air conditioner', 'Single package vertical heat pump'])
      }],
      ['Field-assembled DX system', ->(x) { x.eq(x.dx, 'DXSystemType', 'Field-assembled DX system') }],
      ['Two-pipe / changeover fan coil', lambda { |x|
        x.eq(x.fc, 'FanCoilType', 'Fan coil 2 pipe') ||
          (x.eq(x.fc, 'HVACPipeConfiguration', '2 pipe') &&
            (x.eq(x.hs, 'HeatingMedium', 'Hot water') || x.eq(x.cs, 'CoolingMedium', 'Chilled water')))
      }],
      ['Baseboard / radiator', lambda { |x|
        x.eq(x.z, 'Convection/ConvectionType', 'Perimeter baseboard') || x.eq(x.z, 'Radiant/RadiantType', 'Radiator')
      }],
      ['Heating-only or cooling-only paired system', lambda { |x|
        paired = x.eq(x.dx, 'DXSystemType', 'Packaged terminal air conditioner (PTAC)') ||
                 x.one_of(x.fc, 'FanCoilType', ['Fan coil 4 pipe', 'VRF terminal units']) ||
                 x.eq(x.z, 'Radiant/RadiantType', 'Radiant floor or ceiling')
        hydronic = x.eq(x.fc, 'FanCoilType', 'Fan coil 4 pipe') || x.eq(x.z, 'Radiant/RadiantType', 'Radiant floor or ceiling')
        (x.exists(x.h, 'NoHeating') && paired) || (x.exists(x.c, 'NoCooling') && hydronic)
      }],
      ['Multizone CAV / CAV with terminal reheat', lambda { |x|
        x.eq(x.a, 'TerminalUnit', 'CAV terminal box with reheat') ||
          (x.eq(x.hc, 'ZoningSystemType', 'Multi zone') && x.eq(x.a, 'TerminalUnit', 'CAV terminal box no reheat') && x.conditioned)
      }],
      ['VAV without terminal reheat', lambda { |x|
        x.one_of(x.a, 'TerminalUnit', ['VAV terminal box fan powered no reheat', 'VAV terminal box not fan powered no reheat'])
      }],
      ['Unsupported VAV terminal / reheat pairing', lambda { |x|
        (x.eq(x.a, 'TerminalUnit', 'VAV terminal box not fan powered with reheat') &&
          x.one_of(x.a, 'ReheatSource', ['Local electric resistance', 'Local gas'])) ||
          (x.eq(x.a, 'TerminalUnit', 'VAV terminal box fan powered with reheat') &&
            x.one_of(x.a, 'ReheatSource', ['Heating plant', 'Local gas']))
      }],
      ['Underfloor air distribution', ->(x) { x.eq(x.a, 'AirDeliveryType', 'Low pressure under floor') }],
      ['Evaporative cooling', lambda { |x|
        x.one_of(x.c, 'EvaporativeCooler/EvaporativeCoolingType', ['Direct', 'Direct indirect', 'Indirect', 'Other'])
      }],
      ['Steam / district / solar-thermal heating', lambda { |x|
        !x.hp.nil? && (x.eq(x.hp, 'Boiler/BoilerType', 'Steam') || x.exists(x.hp, 'DistrictHeating') || x.exists(x.hp, 'SolarThermal'))
      }],
      ['Absorption / non-electric chiller or district cooling', lambda { |x|
        !x.cp.nil? && (x.eq(x.cp, 'Chiller/ChillerType', 'Absorption') ||
          x.one_of(x.cp, 'Chiller/ChillerCompressorDriver', ['Steam', 'Gas Turbine', 'Gas Engine']) ||
          x.exists(x.cp, 'DistrictChilledWater'))
      }],
      ['Air-cooled chiller', ->(x) { !x.cn_chiller.nil? && x.exists(x.cn_chiller, 'AirCooled') }]
    ].freeze

    NOT_MAPPABLE_OTHER = {
      'Heat recovery ventilator' => 'Heat-recovery / energy-recovery ventilation',
      'Energy recovery ventilator' => 'Heat-recovery / energy-recovery ventilation',
      'Exhaust only' => 'Exhaust-only / spot exhaust'
    }.freeze

    OTHER_EQUIPMENT_NOT_MAPPABLE = {
      'SpotExhaust' => 'Exhaust-only / spot exhaust',
      'Humidifier' => 'Humidification / dehumidification / air cleaning',
      'Dehumidifier' => 'Humidification / dehumidification / air cleaning',
      'AirCleaner' => 'Humidification / dehumidification / air cleaning',
      'NaturalVentilation' => 'Natural ventilation'
    }.freeze

    VENTILATION_MEASURES = {
      'Supply only' => ['Ventilation Only', 'hvac_ventilation_only'],
      'Dedicated outdoor air system' => ['Dedicated Outdoor Air System', 'hvac_doas']
    }.freeze

    INTEGRATED = ['Integrated with central air distribution', 'Integrated with local air distribution'].freeze

    def self.central_air_absent(x)
      failed = x.exists(x.a, 'ReheatPlantID') ? ['A/ReheatPlantID'] : []
      failed << 'A/FanBased/FanBasedDistributionType' if x.fan_based_distribution(x.a)
      failed
    end

    # @param hvac_systems [REXML::Element] an HVACSystems element (or any parent of HVACSystem elements)
    # @return [Array<Result>]
    def select(hvac_systems)
      Context.nodes(hvac_systems, 'HVACSystem').flat_map { |sys| _select_system(sys) }
    end

    private

    def _select_system(sys)
      index, duplicates = _index(sys)
      sys_id = sys.attributes['ID']
      deliveries = Context.nodes(sys, 'HeatingAndCoolingSystems/Deliveries/Delivery')
      others = Context.nodes(sys, 'OtherHVACSystems/OtherHVACSystem')

      if deliveries.empty? && others.empty?
        principal = Context.texts(sys, 'PrimaryHVACSystemType') + Context.texts(sys, 'PrincipalHVACSystemType')
        message = if principal.empty?
                    'HVACSystem has no Delivery or OtherHVACSystem records.'
                  else
                    "Only family-level data (#{principal.join(', ')}); detailed records are required to select a topology."
                  end
        return [_result(:missing_input, sys_id, [sys_id], [], nil, [message])]
      end

      unless duplicates.empty?
        return [_result(:conflicting_input, sys_id, [sys_id], [], nil, ["Duplicate IDs: #{duplicates.join(', ')}"])]
      end

      ventilation_links = Hash.new { |h, k| h[k] = [] }
      others.each do |other|
        next unless _consumes_deliveries?(sys, other, index)

        Context.nodes(other, 'LinkedDeliveryIDs/LinkedDeliveryID').each do |link|
          ventilation_links[link.attributes['IDref']] << other.attributes['ID']
        end
      end

      results = deliveries.reject { |d| ventilation_links.key?(d.attributes['ID']) }.map do |delivery|
        _select_delivery(sys, delivery, index)
      end
      results + others.map { |other| _select_other(sys, other, index, ventilation_links) }
    end

    # A record whose only content is MechanicalVentilation with VentilationType None or no type
    # (optionally DemandControlVentilation) names no ventilation equipment.
    def _ventilation_annotation?(other)
      type_node = Context.nodes(other, 'OtherHVACType').first
      return false if type_node.nil? || type_node.elements.to_a.map(&:name) != ['MechanicalVentilation']

      mv = type_node.elements.to_a.first
      (mv.elements.to_a.map(&:name) - ['VentilationType', 'DemandControlVentilation']).empty? &&
        [[], ['None']].include?(Context.texts(mv, 'VentilationType'))
    end

    # Outdoor air delivered through the linked deliveries' own air system, not separate equipment.
    def _integrated?(other)
      texts = Context.texts(other, 'Integration')
      !texts.empty? && texts.all? { |t| INTEGRATED.include?(t) }
    end

    def _explicit_no_hvac?(x)
      !x.d.nil? && x.exists(x.h, 'NoHeating') && x.exists(x.c, 'NoCooling') && x.absent(x.d, 'DeliveryType')
    end

    # Ventilation annotations own their linked deliveries only when every one is explicitly
    # unconditioned; otherwise those deliveries are still evaluated as conditioning deliveries.
    def _consumes_deliveries?(sys, other, index)
      return false if _integrated?(other)
      return true unless _ventilation_annotation?(other)

      ids = Context.nodes(other, 'LinkedDeliveryIDs/LinkedDeliveryID').map { |l| l.attributes['IDref'] }
      !ids.empty? && ids.all? { |id| _explicit_no_hvac?(Context.new(sys, index[:delivery][id], index)) }
    end

    def _index(sys)
      kinds = {
        delivery: 'HeatingAndCoolingSystems/Deliveries/Delivery',
        heating_source: 'HeatingAndCoolingSystems/HeatingSources/HeatingSource',
        cooling_source: 'HeatingAndCoolingSystems/CoolingSources/CoolingSource',
        heating_plant: 'Plants/HeatingPlants/HeatingPlant',
        cooling_plant: 'Plants/CoolingPlants/CoolingPlant',
        condenser_plant: 'Plants/CondenserPlants/CondenserPlant',
        other: 'OtherHVACSystems/OtherHVACSystem'
      }
      seen = Hash.new(0)
      index = kinds.transform_values do |path|
        Context.nodes(sys, path).each_with_object({}) do |el, by_id|
          id = el.attributes['ID']
          next if id.nil?

          seen[id] += 1
          by_id[id] = el
        end
      end
      [index, seen.select { |_, count| count > 1 }.keys]
    end

    def _select_delivery(sys, delivery, index)
      x = Context.new(sys, delivery, index)
      ids = [delivery, x.hs, x.cs].compact.map { |el| el.attributes['ID'] }
      premises = _premises(delivery, sys)

      missing = []
      missing << 'Delivery/HeatingSourceID' if x.ref_ids(delivery, 'HeatingSourceID').empty?
      missing << 'Delivery/CoolingSourceID' if x.ref_ids(delivery, 'CoolingSourceID').empty?
      missing << 'LinkedPremises on Delivery or HVACSystem' if premises.empty?
      return _result(:conflicting_input, sys.attributes['ID'], ids, premises, nil, x.conflicts) unless x.conflicts.empty?
      return _result(:missing_input, sys.attributes['ID'], ids, premises, nil, missing.map { |m| "Missing #{m}" }) unless missing.empty?

      hits = DELIVERY_RULES.select { |rule| rule[:required].call(x) }
      not_mappable = NOT_MAPPABLE_DELIVERY.select { |_, test| test.call(x) }.map(&:first)
      return _result(:conflicting_input, sys.attributes['ID'], ids, premises, nil, x.conflicts) unless x.conflicts.empty?

      if hits.length + not_mappable.length > 1
        names = hits.map { |r| r[:configuration] } + not_mappable
        return _result(:conflicting_input, sys.attributes['ID'], ids, premises, nil,
                       ["Delivery matches more than one configuration: #{names.join(', ')}"])
      end

      if not_mappable.length == 1
        return _result(:not_mappable, sys.attributes['ID'], ids, premises, nil,
                       ["#{not_mappable.first}: no buildingsync-measures-gem measure for this configuration."],
                       configuration: not_mappable.first)
      end

      rule = hits.first
      if rule.nil?
        return _result(:missing_input, sys.attributes['ID'], ids, premises, nil,
                       ['Detailed HVAC data does not identify a supported or known configuration.'])
      end

      group_key = _group_key(rule[:group], x)
      if rule[:status] == :mapping_gap
        return _result(:mapping_gap, sys.attributes['ID'], ids, premises, group_key, [rule[:gap]],
                       configuration: rule[:configuration], measure: rule[:measure])
      end

      failures = rule[:absent].call(x).map { |p| "#{p} must be absent" } +
                 rule[:guards].call(x).reject { |_, ok| ok }.map { |name, _| "Guard failed: #{name}" }
      unless failures.empty?
        return _result(:conflicting_input, sys.attributes['ID'], ids, premises, group_key, failures,
                       configuration: rule[:configuration])
      end

      _result(:match, sys.attributes['ID'], ids, premises, group_key, [],
              configuration: rule[:configuration], measure: rule[:measure],
              measure_arguments: rule[:arguments] ? rule[:arguments].call(x) : {})
    end

    def _select_other(sys, other, index, ventilation_links)
      sys_id = sys.attributes['ID']
      other_id = other.attributes['ID']
      linked_ids = Context.nodes(other, 'LinkedDeliveryIDs/LinkedDeliveryID').map { |l| l.attributes['IDref'] }
      ids = [other_id] + linked_ids
      premises = _premises(other, sys)
      type_node = Context.nodes(other, 'OtherHVACType').first
      equipment = type_node.nil? ? [] : type_node.elements.to_a.map(&:name)

      unsupported = equipment.filter_map { |name| OTHER_EQUIPMENT_NOT_MAPPABLE[name] }.uniq
      unless unsupported.empty?
        return _result(:not_mappable, sys_id, ids, premises, nil,
                       unsupported.map { |c| "#{c}: no buildingsync-measures-gem measure for this configuration." },
                       configuration: unsupported.join(', '))
      end

      x_probe = Context.new(sys, other, index)
      ventilation_type = Context.texts(x_probe.mv(other), 'VentilationType')
      if ventilation_type.empty?
        return _result(:missing_input, sys_id, ids, premises, nil,
                       ['OtherHVACSystem does not identify a supported ventilation configuration.'])
      end
      if ventilation_type.length > 1
        return _result(:conflicting_input, sys_id, ids, premises, nil, ['Multiple VentilationType values.'])
      end

      ventilation_type = ventilation_type.first
      if NOT_MAPPABLE_OTHER.key?(ventilation_type)
        configuration = NOT_MAPPABLE_OTHER[ventilation_type]
        return _result(:not_mappable, sys_id, ids, premises, nil,
                       ["#{configuration}: no buildingsync-measures-gem measure creates this equipment."],
                       configuration: configuration)
      end

      if _integrated?(other)
        return _result(:integrated, sys_id, ids, premises, nil,
                       ['Outdoor air is integrated with the linked deliveries; they are selected as conditioning deliveries.'],
                       configuration: 'Integrated outdoor air')
      end

      return _result(:missing_input, sys_id, ids, premises, nil, ['Missing LinkedDeliveryIDs.']) if linked_ids.empty?

      shared = linked_ids.select { |id| ventilation_links[id].length > 1 }
      broken = linked_ids.reject { |id| index[:delivery].key?(id) }
      conflicts = broken.map { |id| "LinkedDeliveryID '#{id}' does not resolve to a Delivery" } +
                  shared.map { |id| "Delivery '#{id}' is linked by more than one OtherHVACSystem" }
      return _result(:conflicting_input, sys_id, ids, premises, nil, conflicts) unless conflicts.empty?

      contexts = linked_ids.map { |id| Context.new(sys, index[:delivery][id], index) }
      linked_conflicts = contexts.flat_map(&:conflicts)
      return _result(:conflicting_input, sys_id, ids, premises, nil, linked_conflicts) unless linked_conflicts.empty?

      if ventilation_type == 'None'
        explicit = contexts.all? do |x|
          x.exists(x.h, 'NoHeating') && x.exists(x.c, 'NoCooling') && x.absent(x.d, 'DeliveryType')
        end
        return _result(:no_hvac, sys_id, ids, premises, nil, [], configuration: 'Explicitly no HVAC') if explicit

        if _ventilation_annotation?(other) && contexts.none? { |x| _explicit_no_hvac?(x) }
          return _result(:no_hvac, sys_id, ids, premises, nil,
                         ['VentilationType None names no ventilation equipment; linked deliveries are selected as conditioning deliveries.'],
                         configuration: 'No separate ventilation equipment')
        end

        return _result(:missing_input, sys_id, ids, premises, nil,
                       ['VentilationType None requires linked deliveries with NoHeating, NoCooling, and no DeliveryType.'])
      end

      configuration, measure = VENTILATION_MEASURES[ventilation_type]
      if configuration.nil?
        return _result(:missing_input, sys_id, ids, premises, nil,
                       ["VentilationType '#{ventilation_type}' does not identify a supported configuration."])
      end

      if contexts.any?(&:conditioned)
        return _result(:not_mappable, sys_id, ids, premises, nil,
                       ['Conditioned DOAS / makeup-air unit: neither ventilation measure creates conditioning coils.'],
                       configuration: 'Conditioned DOAS / heated or cooled makeup-air unit')
      end

      required = contexts.all? do |x|
        x.exists(x.d, 'DeliveryType/CentralAirDistribution') && x.eq(x.a, 'AirDeliveryType', 'Central fan') &&
          x.eq(x.a, 'TerminalUnit', 'CAV terminal box no reheat') && x.eq(x.a, 'ReheatSource', 'None') &&
          x.exists(x.h, 'NoHeating') && x.exists(x.c, 'NoCooling')
      end && Context.texts(other, 'Integration') == ['Stand-alone']
      unless required
        return _result(:missing_input, sys_id, ids, premises, nil,
                       ["#{configuration} requires Stand-alone integration and unconditioned single-duct CAV deliveries."])
      end

      mv = x_probe.mv(other)
      failures = contexts.flat_map { |x| self.class.central_air_absent(x) }.uniq.map { |p| "#{p} must be absent" }
      failures += ['MakeupAirSourceID', 'VentilationControlMethods', 'VentilationZoneControl']
                  .select { |p| x_probe.exists(mv, p) }.map { |p| "MV/#{p} must be absent" }
      failures << 'Guard failed: MV/DemandControlVentilation' unless x_probe.guard(mv, 'DemandControlVentilation', ['false', '0'])
      failures << 'Guard failed: O/PrimaryFuel' unless x_probe.guard(other, 'PrimaryFuel', ELECTRIC)
      failures << 'Guard failed: O/Quantity' unless x_probe.quantity_guard(other, 'Quantity')
      return _result(:conflicting_input, sys_id, ids, premises, nil, failures, configuration: configuration) unless failures.empty?

      _result(:match, sys_id, ids, premises, [:other, other_id], [], configuration: configuration, measure: measure)
    end

    def _group_key(group, x)
      case group
      when :delivery then [:delivery, x.d.attributes['ID']]
      when :cooling_source then [:cooling_source, x.cs_id]
      when :plants then [:plants, x.hp&.attributes&.[]('ID'), x.cp&.attributes&.[]('ID'), x.cn_chiller&.attributes&.[]('ID')]
      end
    end

    # LinkedPremises references as [{ type: 'ThermalZone', id: 'ThermalZone-1' }, ...]. A record
    # without its own links inherits the parent HVACSystem's links.
    def _premises(record, sys)
      own = _linked_premises(record)
      own.empty? ? _linked_premises(sys) : own
    end

    def _linked_premises(record)
      Context.nodes(record, 'LinkedPremises').flat_map do |linked|
        linked.elements.to_a.flat_map do |premise_type|
          premise_type.elements.to_a.filter_map do |link|
            id = link.attributes['IDref']
            { type: premise_type.name, id: id } if id
          end
        end
      end
    end

    def _result(status, sys_id, ids, premises, group_key, messages, configuration: nil, measure: nil, measure_arguments: {})
      Result.new(status: status, configuration: configuration, measure: measure, hvac_system_id: sys_id,
                 record_ids: ids.compact.uniq, premises: premises, group_key: group_key, messages: messages,
                 measure_arguments: measure_arguments)
    end
  end
end
