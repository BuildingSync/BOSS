# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

module BOSS
  # Binds a matched HvacTopologySelector result to model zones.
  #
  # BOSS baseline geometry is generated (create_bar_from_building_type_ratios), so model zones
  # have no BuildingSync IDs. Only whole-building premises can be bound; they resolve to every
  # model zone at run time through buildingsync-measures-gem apply_hvac_topology_to_zone_scope.
  # Zone, space, and section links return :missing_input.
  class HvacTargetBinder
    BINDING_MEASURE = 'apply_hvac_topology_to_zone_scope'
    WHOLE_BUILDING_PREMISES = ['Building', 'Site', 'Facility'].freeze
    STANDARDS_TEMPLATES = ['90.1-2013', '90.1-2016', '90.1-2019'].freeze
    OPERATIONS = ['create', 'replace'].freeze

    Binding = Struct.new(:status, :step, :messages, keyword_init: true)

    # @param result [HvacTopologySelector::Result]
    # @param operation [String] 'create' or 'replace'
    # @param standards_template [String] one of STANDARDS_TEMPLATES
    # @return [Binding] status :bound with an OSW step spec, or the reason it cannot bind
    def bind(result, operation:, standards_template:)
      raise ArgumentError, "Unsupported operation '#{operation}'" if !OPERATIONS.include?(operation)
      if !STANDARDS_TEMPLATES.include?(standards_template)
        raise ArgumentError, "Unsupported standards_template '#{standards_template}'"
      end
      return Binding.new(status: result.status, step: nil, messages: result.messages) if result.status != :match

      unbound = result.premises.reject { |premise| WHOLE_BUILDING_PREMISES.include?(premise[:type]) }
      if result.premises.empty? || !unbound.empty?
        refs = unbound.map { |premise| "#{premise[:type]} #{premise[:id]}" }
        return Binding.new(
          status: :missing_input, step: nil,
          messages: ["#{result.configuration} links #{refs.empty? ? 'no premises' : refs.join(', ')}; " \
                     'only whole-building premises can be bound to generated baseline zones.']
        )
      end

      Binding.new(
        status: :bound,
        step: {
          measure_dir_name: BINDING_MEASURE,
          arguments: {
            topology_measure: result.measure,
            operation: operation,
            zone_scope: 'all_model_zones',
            standards_template: standards_template
          }
        },
        messages: []
      )
    end
  end
end
