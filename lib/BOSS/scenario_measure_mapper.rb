# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'json'
require 'BOSS/constants'
require 'BOSS/boss_logger'

module BOSS
  # Maps one parsed BuildingSync measure (a value from BuildingSyncReader#get_measures)
  # to OpenStudio OSW step specs using scenario_measure_map.json.
  #
  # Lookup tries the technology category element name plus MeasureName first. When that is
  # blank, unmatched, or matches mappings with different steps, it tries SystemCategoryAffected
  # plus MeasureName. Otherwise the measure is unmapped.
  #
  # A step may carry conditional_arguments: an ordered list of { when:, arguments: } rules.
  # A rule applies when every `when` key matches the caller's context; matching rules merge
  # into the step arguments in order, so the last match wins.
  class ScenarioMeasureMapper
    CONDITION_KEYS = [:building_type, :hvac_system_type].freeze
    RULE_KEYS = [:when, :arguments].freeze

    # Ordered phase names from the map's workflow_phases; empty when the map declares none.
    attr_reader :workflow_phases

    def initialize(map_path = SCENARIO_MEASURE_MAP_PATH)
      @map_path = map_path
      mappings = _load_mappings(map_path)
      @mappings_by_technology_category_key = _index_mappings(mappings, :technology_category_element_name)
      @mappings_by_system_category_key = _index_mappings(mappings, :system_category_affected)
    end

    # @param measure [Hash] symbol-keyed measure hash from the reader
    # @param context [Hash, nil] { building_type:, hvac_system_type: } used by conditional_arguments
    # @return [Hash] { measure_id:, steps: [ { measure_dir_name:, arguments: {} } ], warnings: [] }
    def map_measure(measure, context: {})
      context ||= {}
      raise ArgumentError, 'context must be a Hash' if !context.is_a?(Hash)

      technology_category_key = _lookup_key(measure[:technology_category_element_name], measure[:measure_name])
      system_category_key = _lookup_key(measure[:system_category_affected], measure[:measure_name])

      if technology_category_key.nil? && system_category_key.nil?
        return _unmapped_result(
          measure,
          :measure_lookup_key_incomplete,
          'Measure needs MeasureName plus a technology category or SystemCategoryAffected for mapping lookup.'
        )
      end

      technology_category_mappings = @mappings_by_technology_category_key.fetch(technology_category_key, [])
      mapping = technology_category_mappings.first if technology_category_mappings.length == 1
      mapping ||= @mappings_by_system_category_key.fetch(system_category_key, []).first

      if mapping.nil? && technology_category_mappings.length > 1
        return _unmapped_result(
          measure,
          :ambiguous_technology_category_mapping,
          'Measure matches multiple OpenStudio mappings by technology category and MeasureName, ' \
          'and SystemCategoryAffected does not choose one.'
        )
      end

      if mapping.nil?
        return _unmapped_result(measure, :unmapped_measure, 'Measure has no OpenStudio mapping.')
      end

      return {
        measure_id: measure[:measure_id],
        steps: mapping[:steps].map { |step| _effective_step(step, context) },
        warnings: []
      }
    end

    # Maps every MeasureID occurrence of one package scenario, in order. Repeated references
    # are mapped once per occurrence. Step order follows the references and is not the final OSW order.
    # Parser warnings stay with BuildingSyncReader#get_parser_warnings.
    #
    # @param scenario [Hash] one record from BuildingSyncReader#get_package_measure_scenarios
    # @param measures [Hash] BuildingSyncReader#get_measures, keyed by measure ID
    # @param context [Hash, nil] forwarded to #map_measure
    # @return [Hash] { scenario_id:, scenario_name:, report_id:, package_id:,
    #   status: :writable | :skipped, steps: [], skipped_measure_ids: [], warnings: [] }
    def map_package_scenario(scenario, measures, context: {})
      context ||= {}
      raise ArgumentError, 'scenario must be a Hash' if !scenario.is_a?(Hash)
      raise ArgumentError, 'measures must be a Hash' if !measures.is_a?(Hash)
      raise ArgumentError, 'context must be a Hash' if !context.is_a?(Hash)
      raise ArgumentError, 'scenario must be a package_of_measures scenario' if scenario[:scenario_type] != :package_of_measures
      raise ArgumentError, 'scenario measure_ids must be an Array' if !scenario[:measure_ids].is_a?(Array)

      scenario_context = {
        report_id: scenario[:report_id],
        scenario_id: scenario[:scenario_id],
        package_id: scenario[:package_id]
      }
      steps = []
      skipped_measure_ids = []
      warnings = []

      scenario[:measure_ids].each do |measure_idref|
        measure = _normalize(measure_idref).nil? ? nil : measures[measure_idref]
        if measure.nil?
          code, message = if _normalize(measure_idref).nil?
                            [:missing_measure_idref, 'MeasureID is missing IDref.']
                          else
                            [:unresolved_measure_idref, 'Package references an unknown measure ID.']
                          end
          warnings << _scenario_warning(code, message, scenario_context.merge(measure_idref:))
          skipped_measure_ids << measure_idref
          next
        end

        result = map_measure(measure, context:)
        steps.concat(result[:steps])
        skipped_measure_ids << measure_idref if result[:steps].empty?
        warnings.concat(result[:warnings].map { |warning| warning.merge(scenario_context) })
      end

      if steps.empty?
        warnings << _scenario_warning(
          :package_has_no_mapped_measures,
          'Package scenario has no mapped OpenStudio steps; scenario workflow will be skipped.',
          scenario_context
        )
      end

      return _deep_copy(
        scenario_id: scenario[:scenario_id],
        scenario_name: scenario[:scenario_name],
        report_id: scenario[:report_id],
        package_id: scenario[:package_id],
        status: steps.empty? ? :skipped : :writable,
        steps:,
        skipped_measure_ids:,
        warnings:
      )
    end

    private

    def _scenario_warning(code, message, context)
      BOSS.BOSS_logger.warn(
        "BOSS.ScenarioMeasureMapper: #{message} " \
        "(#{context.map { |key, value| "#{key}: #{value.inspect}" }.join(', ')})"
      )

      return { code:, severity: :warning, message: }.merge(context)
    end

    def _load_mappings(map_path)
      raise ArgumentError, "Scenario measure map '#{map_path}' does not exist" if !File.file?(map_path.to_s)

      begin
        map = JSON.parse(File.read(map_path), symbolize_names: true)
      rescue JSON::ParserError => e
        raise ArgumentError, "Scenario measure map '#{map_path}' is not valid JSON: #{e.message}"
      end

      mappings = map.is_a?(Hash) ? map[:mappings] : nil
      raise ArgumentError, "Scenario measure map '#{map_path}' must define a 'mappings' array" if !mappings.is_a?(Array)

      @workflow_phases = _load_workflow_phases(map, map_path)

      mappings.each_with_index do |mapping, mapping_index|
        Array(mapping.is_a?(Hash) ? mapping[:steps] : nil).each_with_index do |step, step_index|
          next if !step.is_a?(Hash)

          location = "Scenario measure map '#{map_path}' mappings[#{mapping_index}].steps[#{step_index}]"
          _validate_workflow_phase(step, location)
          next if !step.key?(:conditional_arguments)

          _validate_conditional_arguments(step[:conditional_arguments], "#{location}.conditional_arguments")
        end
      end

      return mappings
    end

    def _load_workflow_phases(map, map_path)
      return [].freeze if !map.key?(:workflow_phases)

      phases = map[:workflow_phases]
      location = "Scenario measure map '#{map_path}' workflow_phases"
      if !phases.is_a?(Array) || phases.empty? || phases.any? { |phase| !phase.is_a?(String) || phase.strip.empty? }
        raise ArgumentError, "#{location} must be a non-empty array of non-blank strings"
      end
      raise ArgumentError, "#{location} must not contain duplicates" if phases.uniq.length != phases.length

      return phases.map(&:freeze).freeze
    end

    # Maps without workflow_phases are legacy maps and may not tag steps. Maps that declare
    # phases must tag every step with a declared phase.
    def _validate_workflow_phase(step, location)
      if @workflow_phases.empty?
        return if !step.key?(:workflow_phase)

        raise ArgumentError, "#{location}.workflow_phase requires a top-level workflow_phases array"
      end

      return if @workflow_phases.include?(step[:workflow_phase])

      raise ArgumentError,
            "#{location}.workflow_phase must be one of #{@workflow_phases.inspect}, got #{step[:workflow_phase].inspect}"
    end

    def _validate_conditional_arguments(rules, location)
      raise ArgumentError, "#{location} must be an array" if !rules.is_a?(Array)

      rules.each_with_index do |rule, rule_index|
        rule_location = "#{location}[#{rule_index}]"
        raise ArgumentError, "#{rule_location} must be an object" if !rule.is_a?(Hash)

        unknown_keys = rule.keys - RULE_KEYS
        raise ArgumentError, "#{rule_location} has unknown keys #{unknown_keys.inspect}" if unknown_keys.any?

        predicates = rule[:when]
        if !predicates.is_a?(Hash) || predicates.empty?
          raise ArgumentError, "#{rule_location}.when must be a non-empty object"
        end

        predicates.each do |key, value|
          raise ArgumentError, "#{rule_location}.when has unknown key '#{key}'" if !CONDITION_KEYS.include?(key)

          candidates = value.is_a?(Array) ? value : [value]
          if candidates.empty? || candidates.any? { |candidate| !candidate.is_a?(String) || _normalize(candidate).nil? }
            raise ArgumentError, "#{rule_location}.when.#{key} must be a non-blank string or non-empty array of them"
          end
        end

        arguments = rule[:arguments]
        if !arguments.is_a?(Hash) || arguments.empty?
          raise ArgumentError, "#{rule_location}.arguments must be a non-empty object"
        end

        arguments.each do |name, value|
          raise ArgumentError, "#{rule_location}.arguments has a blank name" if _normalize(name).nil?
          if [String, Numeric, TrueClass, FalseClass].none? { |type| value.is_a?(type) }
            raise ArgumentError, "#{rule_location}.arguments.#{name} must be a string, number, or boolean"
          end
        end
      end
    end

    def _effective_step(step, context)
      effective_step = _deep_copy(step)
      rules = effective_step.delete(:conditional_arguments) || []
      rules.each do |rule|
        (effective_step[:arguments] ||= {}).merge!(rule[:arguments]) if _rule_matches?(rule, context)
      end

      return effective_step
    end

    def _rule_matches?(rule, context)
      return rule[:when].all? do |key, expected|
        actual = context[key]
        next false if !actual.is_a?(String) || _normalize(actual).nil?

        Array(expected).any? { |candidate| _normalize(candidate) == _normalize(actual) }
      end
    end

    # Groups mappings by [category, MeasureName] in JSON order. Entries with identical steps
    # collapse to one, so only mappings with different steps make a key ambiguous.
    def _index_mappings(mappings, category_field)
      mappings_by_key = {}
      mappings.each do |mapping|
        key = _lookup_key(mapping[category_field], mapping[:measure_name])
        next if key.nil?

        key_mappings = (mappings_by_key[key] ||= [])
        key_mappings << mapping if key_mappings.none? { |key_mapping| key_mapping[:steps] == mapping[:steps] }
      end

      return mappings_by_key.freeze
    end

    def _lookup_key(category, measure_name)
      category_key = _normalize(category)
      measure_name_key = _normalize(measure_name)
      return nil if category_key.nil? || measure_name_key.nil?

      return [category_key, measure_name_key]
    end

    def _normalize(value)
      normalized = value.to_s.strip.squeeze(' ').downcase
      return normalized.empty? ? nil : normalized
    end

    def _unmapped_result(measure, code, message)
      warning = {
        code:,
        severity: :warning,
        message:,
        measure_id: measure[:measure_id],
        system_category_affected: measure[:system_category_affected],
        technology_category_element_name: measure[:technology_category_element_name],
        measure_name: measure[:measure_name]
      }
      BOSS.BOSS_logger.warn(
        "BOSS.ScenarioMeasureMapper: #{message} " \
        "(measure_id: #{warning[:measure_id].inspect}, " \
        "system_category_affected: #{warning[:system_category_affected].inspect}, " \
        "technology_category_element_name: #{warning[:technology_category_element_name].inspect}, " \
        "measure_name: #{warning[:measure_name].inspect})"
      )

      return {
        measure_id: measure[:measure_id],
        steps: [],
        warnings: [warning]
      }
    end

    def _deep_copy(value)
      return Marshal.load(Marshal.dump(value))
    end
  end
end
