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
  class ScenarioMeasureMapper
    def initialize(map_path = SCENARIO_MEASURE_MAP_PATH)
      @map_path = map_path
      mappings = _load_mappings(map_path)
      @mappings_by_technology_category_key = _index_mappings(mappings, :technology_category_element_name)
      @mappings_by_system_category_key = _index_mappings(mappings, :system_category_affected)
    end

    # @param measure [Hash] symbol-keyed measure hash from the reader
    # @return [Hash] { measure_id:, steps: [ { measure_dir_name:, arguments: {} } ], warnings: [] }
    def map_measure(measure)
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
        steps: _deep_copy(mapping[:steps]),
        warnings: []
      }
    end

    private

    def _load_mappings(map_path)
      raise ArgumentError, "Scenario measure map '#{map_path}' does not exist" if !File.file?(map_path.to_s)

      begin
        map = JSON.parse(File.read(map_path), symbolize_names: true)
      rescue JSON::ParserError => e
        raise ArgumentError, "Scenario measure map '#{map_path}' is not valid JSON: #{e.message}"
      end

      mappings = map.is_a?(Hash) ? map[:mappings] : nil
      raise ArgumentError, "Scenario measure map '#{map_path}' must define a 'mappings' array" if !mappings.is_a?(Array)

      return mappings
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
