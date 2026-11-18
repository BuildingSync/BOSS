# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'rexml/document'
require 'BOSS/hvac_topology_selector'
require 'BOSS/hvac_target_binder'

module BOSS
  # Decides whether the baseline builds HVAC from split topology measures or keeps
  # create_typical_building_from_model HVAC.
  #
  # Every binder step resolves to all model zones, so a topology plan allows one
  # conditioning configuration plus, for zone-equipment configurations only, one
  # ventilation configuration (DOAS create rejects zones already on an air loop).
  # Results with the same measure and measure arguments are one configuration. Its
  # Section links count as whole-building when they cover the building's sections.
  class BaselineHvacPlanner
    SIZING_MEASURE = 'apply_standard_hvac_sizing_and_efficiency'
    VENTILATION_MEASURES = HvacTopologySelector::VENTILATION_MEASURES.values.map(&:last).freeze
    ZONE_EQUIPMENT_MEASURES = ['hvac_ptac', 'hvac_pthp', 'hvac_four_pipe_fan_coil', 'hvac_vrf'].freeze

    Plan = Struct.new(:status, :steps, :messages, keyword_init: true) do
      def topology? = status == :topology
    end

    def initialize(selector: HvacTopologySelector.new, binder: HvacTargetBinder.new)
      @selector = selector
      @binder = binder
    end

    # @param hvac_systems [REXML::Element, nil] the facility HVACSystems element
    # @param standards_template [String] baseline create_typical template
    # @param operation [String] binder operation for the conditioning step; ventilation is always created
    # @param include_system_ids [Array<String>, nil] when given, only these HVACSystems are planned
    # @param exclude_system_ids [Array<String>] HVACSystems left out, such as proposed scenario systems
    # @return [Plan] :topology with ordered OSW steps, or :fallback with the reasons
    def plan(hvac_systems, standards_template, operation: 'create', include_system_ids: nil, exclude_system_ids: [])
      return fallback(['No HVACSystems in the facility.']) if hvac_systems.nil?

      if !HvacTargetBinder::STANDARDS_TEMPLATES.include?(standards_template)
        return fallback(["Template '#{standards_template}' is not supported by the split HVAC measures " \
                         "(#{HvacTargetBinder::STANDARDS_TEMPLATES.join(', ')})."])
      end

      results = @selector.select(hvac_systems).select do |result|
        (include_system_ids.nil? || include_system_ids.include?(result.hvac_system_id)) &&
          !exclude_system_ids.include?(result.hvac_system_id)
      end
      return fallback(['No HVACSystem records.']) if results.empty?

      unmatched = results.reject { |result| result.status == :match }
      return fallback(unmatched.map { |result| describe(result, result.status, result.messages) }) if !unmatched.empty?

      groups = results.group_by { |result| [result.measure, result.measure_arguments || {}] }.values
                      .map { |members| merge(members, hvac_systems) }
      ventilation, conditioning = groups.partition { |result| VENTILATION_MEASURES.include?(result.measure) }
      problems = []
      if conditioning.length != 1
        problems << "Expected one conditioning configuration, found #{conditioning.length}; " \
                    'zone-level binding is not supported.'
      end
      problems << "Expected at most one ventilation configuration, found #{ventilation.length}." if ventilation.length > 1
      if !ventilation.empty? && conditioning.length == 1 && !ZONE_EQUIPMENT_MEASURES.include?(conditioning.first.measure)
        problems << "#{ventilation.first.configuration} cannot be added to zones served by " \
                    "#{conditioning.first.configuration} air loops."
      end
      return fallback(problems) if !problems.empty?

      bindings = conditioning.map { |result| [result, @binder.bind(result, operation:, standards_template:)] } +
                 ventilation.map { |result| [result, @binder.bind(result, operation: 'create', standards_template:)] }
      unbound = bindings.reject { |_, binding| binding.status == :bound }
      return fallback(unbound.map { |result, binding| describe(result, binding.status, binding.messages) }) if !unbound.empty?

      sizing_step = { measure_dir_name: SIZING_MEASURE, arguments: { standards_template: } }
      Plan.new(status: :topology, steps: bindings.map { |_, binding| binding.step } + [sizing_step], messages: [])
    end

    # @return [Array<Hash>] premises, or one Building premise when Section links cover the building
    def self.normalize_premises(premises, document)
      building_id = covered_building_id(premises, document)
      building_id ? [{ type: 'Building', id: building_id }] : premises
    end

    # @return [String, nil] the building ID when every premise is a Section of the one
    #   building and they include its 'Whole building' section or all of its other
    #   non-empty sections
    def self.covered_building_id(premises, document)
      return nil if premises.empty? || !premises.all? { |premise| premise[:type] == 'Section' }

      buildings = REXML::XPath.match(document, "//*[local-name()='Building'][@ID]")
      return nil if buildings.length != 1

      sections = REXML::XPath.match(buildings.first, "*[local-name()='Sections']/*[local-name()='Section'][@ID]")
      section_ids = sections.map { |section| section.attributes['ID'] }
      linked = premises.map { |premise| premise[:id] }
      return nil if !(linked - section_ids).empty?

      whole, parts = sections.partition do |section|
        REXML::XPath.first(section, "*[local-name()='SectionType']")&.text == 'Whole building'
      end
      whole_linked = whole.any? { |section| linked.include?(section.attributes['ID']) }
      parts_linked = !parts.empty? && parts.all? do |section|
        section.elements.empty? || linked.include?(section.attributes['ID'])
      end
      whole_linked || parts_linked ? buildings.first.attributes['ID'] : nil
    end

    private

    def merge(members, hvac_systems)
      merged = members.first.dup
      merged.premises = self.class.normalize_premises(members.flat_map { |member| member.premises || [] }.uniq,
                                                      hvac_systems.document)
      merged
    end

    def fallback(messages)
      Plan.new(status: :fallback, steps: [], messages:)
    end

    def describe(result, status, messages)
      label = result.configuration || result.hvac_system_id || 'HVACSystem'
      "#{label} (#{status}): #{messages.join(' ')}"
    end
  end
end
