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
  class HvacTargetBinder
    BINDING_MEASURE = 'apply_hvac_topology_to_zone_scope'
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

    private

    def step(result, operation, standards_template, zone_names)
      scope = zone_names ? { zone_scope: 'explicit_zone_names', zone_names_json: JSON.generate(zone_names.uniq) } : { zone_scope: 'all_model_zones' }
      {
        measure_dir_name: BINDING_MEASURE,
        arguments: { topology_measure: result.measure, operation: operation, **scope, standards_template: standards_template }
      }
    end
  end
end
