# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'rexml/document'
require 'BOSS/baseline_hvac_planner'
require 'BOSS/hvac_topology_selector'
require 'BOSS/hvac_target_binder'

module BOSS
  # Plans split HVAC measure steps for one BuildingSync scenario measure.
  #
  # - Replacement with AlternativeSystemReplacement HVACSystems: the alternative systems go
  #   through the topology selector and bind with operation 'replace'. The replaced systems
  #   must be every existing HVACSystem, because generated zones cannot be split.
  # - ModificationRetrocommissioning with ModifiedSystem HVACSystems: source efficiencies
  #   stated as COP or Thermal Efficiency become modify_existing_hvac_equipment_efficiencies steps.
  # - Otherwise, a MeasureName in NAMED_TOPOLOGIES names exactly one topology and replaces
  #   whole-building HVAC.
  #
  # Measures that match none of these are :not_hvac and fall through to the JSON map.
  class ScenarioHvacPlanner
    PHASE = 'hvac_equipment'
    MODIFIER_PHASE = 'hvac_modifiers'
    EFFICIENCY_MODIFIER = 'modify_existing_hvac_equipment_efficiencies'
    # MeasureName => [configuration, topology measure]. Only names that identify one topology.
    NAMED_TOPOLOGIES = {
      'Install variable refrigerant flow system' => ['VRF Terminal Unit', 'hvac_vrf']
    }.freeze

    Result = Struct.new(:status, :steps, :messages, keyword_init: true)

    # @return [Array<String>] HVACSystem IDs that measures name as alternatives or modified systems
    def self.proposed_system_ids(hvac_systems)
      return [] if hvac_systems.nil?

      system_ids = _system_ids(hvac_systems)
      refs = REXML::XPath.match(
        hvac_systems.document,
        "//*[local-name()='Measure']/*[local-name()='TypeOfMeasure']//" \
        "*[local-name()='AlternativeSystemReplacement' or local-name()='ModifiedSystem']/@IDref"
      ).map(&:value)
      refs.uniq & system_ids
    end

    def self._system_ids(hvac_systems)
      REXML::XPath.match(hvac_systems, "*[local-name()='HVACSystem']/@ID").map(&:value)
    end

    # @param hvac_systems [REXML::Element, nil] the facility HVACSystems element
    # @param document [REXML::Document] the BuildingSync document
    # @param standards_template [String] template for retrofit HVAC
    def initialize(hvac_systems, document, standards_template, planner: BaselineHvacPlanner.new, binder: HvacTargetBinder.new)
      @hvac_systems = hvac_systems
      @document = document
      @standards_template = standards_template
      @planner = planner
      @binder = binder
      @system_ids = hvac_systems.nil? ? [] : self.class._system_ids(hvac_systems)
      @proposed_ids = self.class.proposed_system_ids(hvac_systems)
    end

    # @param measure [Hash] symbol-keyed measure hash from BuildingSyncReader#get_measures
    # @return [Result] :mapped with OSW steps, :unmapped with reasons, or :not_hvac
    def plan(measure)
      measure_xml = REXML::XPath.first(@document, "//*[local-name()='Measure'][@ID=$id]", nil,
                                       { 'id' => measure[:measure_id].to_s })
      return not_hvac if measure_xml.nil?

      alternatives = refs(measure_xml, 'Replacements', 'Replacement', 'AlternativeSystemReplacement')
      modified = refs(measure_xml, 'ModificationRetrocommissions', 'ModificationRetrocommissioning', 'ModifiedSystem')
      return plan_replacement(measure_xml, alternatives) if !alternatives.empty?
      return plan_modification(measure_xml, modified) if !modified.empty?
      return plan_named_replacement(measure_xml, measure[:measure_name]) if NAMED_TOPOLOGIES.key?(measure[:measure_name])

      not_hvac
    end

    private

    # HVACSystem IDs referenced by TypeOfMeasure/<names...>/@IDref.
    def refs(measure_xml, *names)
      path = (['TypeOfMeasure'] + names).map { |name| "*[local-name()='#{name}']" }.join('/')
      REXML::XPath.match(measure_xml, "#{path}/@IDref").map(&:value).uniq & @system_ids
    end

    def plan_replacement(measure_xml, alternatives)
      return unmapped([template_message]) if template_message

      replaced = refs(measure_xml, 'Replacements', 'Replacement', 'ExistingSystemReplaced')
      existing = @system_ids - @proposed_ids
      if replaced.empty?
        return unmapped(['Replacement names no ExistingSystemReplaced HVACSystem.'])
      end

      if !(existing - replaced).empty?
        return unmapped(["Replacement leaves #{(existing - replaced).join(', ')} in place; " \
                         'partial HVAC replacement is not supported.'])
      end

      hvac_plan = @planner.plan(@hvac_systems, @standards_template, operation: 'replace', include_system_ids: alternatives)
      return unmapped(hvac_plan.messages) if !hvac_plan.topology?

      mapped(hvac_plan.steps)
    end

    def plan_named_replacement(measure_xml, measure_name)
      return unmapped([template_message]) if template_message

      configuration, topology = NAMED_TOPOLOGIES.fetch(measure_name)
      result = HvacTopologySelector::Result.new(
        status: :match, configuration:, measure: topology, hvac_system_id: nil, record_ids: [],
        premises: BaselineHvacPlanner.normalize_premises(linked_premises(measure_xml), @document),
        group_key: nil, messages: [], measure_arguments: {}
      )
      binding = @binder.bind(result, operation: 'replace', standards_template: @standards_template)
      return unmapped(binding.messages) if binding.status != :bound

      mapped([binding.step, sizing_step])
    end

    def plan_modification(measure_xml, modified)
      affected = refs(measure_xml, 'ModificationRetrocommissions', 'ModificationRetrocommissioning', 'ExistingSystemAffected')
      return unmapped(['ModificationRetrocommissioning names no ExistingSystemAffected HVACSystem.']) if affected.empty?

      settings = {}
      problems = []
      premises = []
      modified.each do |system_id|
        system = REXML::XPath.first(@hvac_systems, "*[local-name()='HVACSystem'][@ID=$id]", nil, { 'id' => system_id })
        premises.concat(linked_premises(system))
        source_efficiencies(system).each do |metric, value, problem|
          next problems << "#{system_id}: #{problem}" if problem

          if settings.key?(metric) && settings[metric] != value
            problems << "#{system_id}: conflicting #{metric} values #{settings[metric]} and #{value}."
          end
          settings[metric] ||= value
        end
      end
      return unmapped(problems) if !problems.empty?
      return unmapped(['ModifiedSystem states no COP or Thermal Efficiency source values.']) if settings.empty?

      premises = BaselineHvacPlanner.normalize_premises(premises.uniq, @document)
      bindings = settings.map do |metric, value|
        @binder.bind_modifier(modifier_measure: EFFICIENCY_MODIFIER,
                              modifier_arguments: { efficiency_metric: metric, efficiency_value: value }, premises:)
      end
      unbound = bindings.reject { |binding| binding.status == :bound }
      return unmapped(unbound.flat_map(&:messages).uniq) if !unbound.empty?

      Result.new(status: :mapped, steps: bindings.map { |binding| binding.step.merge(workflow_phase: MODIFIER_PHASE) },
                 messages: [])
    end

    # @return [Array<Array>] [metric, value, nil] or [nil, nil, problem] per source with an efficiency value
    def source_efficiencies(system)
      cooling = sources(system, 'CoolingSources/CoolingSource', 'AnnualCoolingEfficiency').map do |source, value, units|
        dx = node(source, 'CoolingSourceType/DX')
        next [nil, nil, "#{id(source)} is not DX; only DX cooling COP is supported."] if dx.nil?

        metric = text(dx, 'DXSystemType') == 'Variable refrigerant flow' ? 'vrf_cooling_cop' : 'dx_cooling_cop'
        cop(source, metric, value, units)
      end
      heating = sources(system, 'HeatingSources/HeatingSource', 'AnnualHeatingEfficiency').map do |source, value, units|
        heating_efficiency(source, value, units)
      end
      cooling + heating
    end

    def heating_efficiency(source, value, units)
      type = node(source, 'HeatingSourceType')
      if node(type, 'HeatPump')
        cooling_id = REXML::XPath.first(type, "*[local-name()='HeatPump']/*[local-name()='CoolingSourceID']/@IDref")&.value
        cooling = cooling_id && REXML::XPath.first(@hvac_systems, "//*[local-name()='CoolingSource'][@ID=$id]", nil,
                                                   { 'id' => cooling_id })
        vrf = cooling && text(node(cooling, 'CoolingSourceType/DX'), 'DXSystemType') == 'Variable refrigerant flow'
        return cop(source, vrf ? 'vrf_heating_cop' : 'dx_heating_cop', value, units)
      end
      if node(type, 'Furnace') && text(source, 'PrimaryFuel') == 'Natural gas'
        return fraction(source, 'gas_burner_efficiency', value, units)
      end
      return fraction(source, 'electric_heating_efficiency', value, units) if node(type, 'ElectricResistance')

      [nil, nil, "#{id(source)} heating type is not supported for efficiency changes."]
    end

    def cop(source, metric, value, units)
      return [nil, nil, "#{id(source)} efficiency units '#{units}' are not COP."] if units != 'COP'
      return [nil, nil, "#{id(source)} COP must be positive."] if value <= 0

      [metric, value, nil]
    end

    def fraction(source, metric, value, units)
      return [nil, nil, "#{id(source)} efficiency units '#{units}' are not Thermal Efficiency."] if units != 'Thermal Efficiency'
      return [nil, nil, "#{id(source)} Thermal Efficiency must be in (0, 1]."] if value <= 0 || value > 1

      [metric, value, nil]
    end

    # [source, value, units] for sources that state an efficiency value.
    def sources(system, path, prefix)
      parent, child = path.split('/')
      REXML::XPath.match(system, "*[local-name()='HeatingAndCoolingSystems']/*[local-name()='#{parent}']/" \
                                 "*[local-name()='#{child}']").filter_map do |source|
        raw = text(source, "#{prefix}Value")
        next if raw.nil? || raw.strip.empty?

        value = Float(raw, exception: false)
        next [source, -1.0, text(source, "#{prefix}Units")] if value.nil?

        [source, value, text(source, "#{prefix}Units")]
      end
    end

    def linked_premises(xml)
      REXML::XPath.match(xml, "*[local-name()='LinkedPremises']/*").flat_map do |premise_type|
        premise_type.elements.to_a.filter_map do |link|
          link.attributes['IDref'] && { type: premise_type.name, id: link.attributes['IDref'] }
        end
      end
    end

    def node(xml, path)
      return nil if xml.nil?

      REXML::XPath.first(xml, path.split('/').map { |name| "*[local-name()='#{name}']" }.join('/'))
    end

    def text(xml, path) = node(xml, path)&.text&.strip
    def id(xml) = xml.attributes['ID'] || xml.name

    def template_message
      return nil if HvacTargetBinder::STANDARDS_TEMPLATES.include?(@standards_template)

      "Template '#{@standards_template}' is not supported by the split HVAC measures."
    end

    def sizing_step
      { measure_dir_name: BaselineHvacPlanner::SIZING_MEASURE, arguments: { standards_template: @standards_template } }
    end

    def mapped(steps)
      Result.new(status: :mapped, steps: steps.map { |step| step.merge(workflow_phase: PHASE) }, messages: [])
    end

    def unmapped(messages)
      Result.new(status: :unmapped, steps: [], messages:)
    end

    def not_hvac
      Result.new(status: :not_hvac, steps: [], messages: [])
    end
  end
end
