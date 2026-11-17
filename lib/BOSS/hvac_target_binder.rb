# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'json'

module BOSS
  # Binds a matched HvacTopologySelector result to model zones.
  #
  # BOSS baseline geometry is generated (create_bar_from_building_type_ratios), so model zones
  # have no BuildingSync IDs. Whole-building premises resolve to every model zone at run time
  # through buildingsync-measures-gem apply_hvac_topology_to_zone_scope. Other premises bind only
  # when the caller passes the exact model zone names; otherwise they return :missing_input.
  # bind_modifier does the same for modify_existing_* measures through
  # apply_hvac_modifier_to_object_scope, which resolves model object names at run time.
  class HvacTargetBinder
    BINDING_MEASURE = 'apply_hvac_topology_to_zone_scope'
    MODIFIER_BINDING_MEASURE = 'apply_hvac_modifier_to_object_scope'
    # Modifier measure => its target-names argument, which the binding measure fills.
    MODIFIER_TARGETS = {
      'modify_existing_air_loop_controls' => 'target_air_loop_names',
      'modify_existing_heat_recovery' => 'target_heat_exchanger_names',
      'modify_existing_hvac_equipment_efficiencies' => 'target_object_names',
      'modify_existing_plant_equipment' => 'target_plant_equipment_names',
      'modify_existing_plant_loop_temperatures' => 'target_plant_loop_names'
    }.freeze
    PLANT_LOOP_TYPES = ['Heating', 'Cooling', 'Condenser'].freeze
    WHOLE_BUILDING_PREMISES = ['Building', 'Site', 'Facility'].freeze
    STANDARDS_TEMPLATES = ['90.1-2013', '90.1-2016', '90.1-2019'].freeze
    OPERATIONS = ['create', 'replace'].freeze

    Binding = Struct.new(:status, :step, :messages, keyword_init: true)

    # @param result [HvacTopologySelector::Result]
    # @param operation [String] 'create' or 'replace'
    # @param standards_template [String] one of STANDARDS_TEMPLATES
    # @param zone_names [Array<String>, nil] exact model zone names for the result's premises;
    #   when given, the step uses zone_scope explicit_zone_names instead of all_model_zones
    # @return [Binding] status :bound with an OSW step spec, or the reason it cannot bind
    def bind(result, operation:, standards_template:, zone_names: nil)
      raise ArgumentError, "Unsupported operation '#{operation}'" if !OPERATIONS.include?(operation)
      if !STANDARDS_TEMPLATES.include?(standards_template)
        raise ArgumentError, "Unsupported standards_template '#{standards_template}'"
      end
      if !zone_names.nil? && (zone_names.empty? || !zone_names.all? { |name| name.is_a?(String) && !name.strip.empty? })
        raise ArgumentError, 'zone_names must be a non-empty array of non-empty strings'
      end
      return Binding.new(status: result.status, step: nil, messages: result.messages) if result.status != :match
      return Binding.new(status: :bound, step: step(result, operation, standards_template, zone_names), messages: []) if zone_names

      unbound = result.premises.reject { |premise| WHOLE_BUILDING_PREMISES.include?(premise[:type]) }
      if result.premises.empty? || !unbound.empty?
        refs = unbound.map { |premise| "#{premise[:type]} #{premise[:id]}" }
        return Binding.new(
          status: :missing_input, step: nil,
          messages: ["#{result.configuration} links #{refs.empty? ? 'no premises' : refs.join(', ')}; " \
                     'only whole-building premises can be bound to generated baseline zones.']
        )
      end

      Binding.new(status: :bound, step: step(result, operation, standards_template, nil), messages: [])
    end

    # @param modifier_measure [String] one of MODIFIER_TARGETS keys
    # @param modifier_arguments [Hash] the modifier's arguments other than its target-names argument
    # @param premises [Array<Hash>] BuildingSync premises ({ type:, id: }) the change applies to
    # @param object_names [Array<String>, nil] exact model object names; when given, the step uses
    #   object_scope explicit_object_names instead of all_matching_objects
    # @param plant_loop_type [String, nil] Heating, Cooling, or Condenser; required for
    #   modify_existing_plant_loop_temperatures without object_names
    # @return [Binding] status :bound with an OSW step spec, or :missing_input
    def bind_modifier(modifier_measure:, modifier_arguments:, premises:, object_names: nil, plant_loop_type: nil)
      target_key = MODIFIER_TARGETS[modifier_measure]
      raise ArgumentError, "Unsupported modifier_measure '#{modifier_measure}'" if target_key.nil?
      raise ArgumentError, 'modifier_arguments must be a Hash' if !modifier_arguments.is_a?(Hash)
      if modifier_arguments.key?(target_key) || modifier_arguments.key?(target_key.to_sym)
        raise ArgumentError, "modifier_arguments must not set #{target_key}"
      end
      if !plant_loop_type.nil? && !PLANT_LOOP_TYPES.include?(plant_loop_type)
        raise ArgumentError, "Unsupported plant_loop_type '#{plant_loop_type}'"
      end
      if !object_names.nil? && (object_names.empty? || !object_names.all? { |name| name.is_a?(String) && !name.strip.empty? })
        raise ArgumentError, 'object_names must be a non-empty array of non-empty strings'
      end

      if object_names.nil?
        unbound = premises.reject { |premise| WHOLE_BUILDING_PREMISES.include?(premise[:type]) }
        if premises.empty? || !unbound.empty?
          refs = unbound.map { |premise| "#{premise[:type]} #{premise[:id]}" }
          return Binding.new(
            status: :missing_input, step: nil,
            messages: ["#{modifier_measure} links #{refs.empty? ? 'no premises' : refs.join(', ')}; " \
                       'only whole-building premises can be bound to generated baseline objects.']
          )
        end
        if modifier_measure == 'modify_existing_plant_loop_temperatures' && plant_loop_type.nil?
          return Binding.new(status: :missing_input, step: nil,
                             messages: ["#{modifier_measure} needs a plant_loop_type to bind to all matching loops."])
        end
      end

      scope = if object_names
                { object_scope: 'explicit_object_names', object_names_json: JSON.generate(object_names.uniq) }
              else
                { object_scope: 'all_matching_objects' }
              end
      scope[:plant_loop_type] = plant_loop_type if plant_loop_type
      step = {
        measure_dir_name: MODIFIER_BINDING_MEASURE,
        arguments: { modifier_measure: modifier_measure, **scope,
                     modifier_arguments_json: JSON.generate(modifier_arguments) }
      }
      Binding.new(status: :bound, step: step, messages: [])
    end

    private

    def step(result, operation, standards_template, zone_names)
      scope = zone_names ? { zone_scope: 'explicit_zone_names', zone_names_json: JSON.generate(zone_names.uniq) } : { zone_scope: 'all_model_zones' }
      arguments = { topology_measure: result.measure, operation: operation, **scope, standards_template: standards_template }
      extra = result.measure_arguments || {}
      arguments[:topology_arguments_json] = JSON.generate(extra) if !extra.empty?
      { measure_dir_name: BINDING_MEASURE, arguments: arguments }
    end
  end
end
