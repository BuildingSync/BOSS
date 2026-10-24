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
  class ScenarioMeasureMapper
    def initialize(map_path = SCENARIO_MEASURE_MAP_PATH)
      @map_path = map_path
      @mappings_by_key = _index_mappings(_load_mappings(map_path))
    end

    # @param measure [Hash] symbol-keyed measure hash from the reader
    # @return [Hash] { measure_id:, steps: [ { measure_dir_name:, arguments: {} } ], warnings: [] }
    def map_measure(measure)
      system_category_affected = measure[:system_category_affected]
      measure_name = measure[:measure_name]
      key = _lookup_key(system_category_affected, measure_name)

      if key.nil?
        return _unmapped_result(
          measure,
          :measure_lookup_key_incomplete,
          'Measure is missing SystemCategoryAffected or MeasureName needed for mapping lookup.'
        )
      end

      mapping = @mappings_by_key[key]
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

    def _index_mappings(mappings)
      mappings_by_key = {}
      mappings.each do |mapping|
        key = _lookup_key(mapping[:system_category_affected], mapping[:measure_name])
        next if key.nil? || mappings_by_key.key?(key)

        mappings_by_key[key] = mapping
      end

      return mappings_by_key.freeze
    end

    def _lookup_key(system_category_affected, measure_name)
      system_category_key = _normalize(system_category_affected)
      measure_name_key = _normalize(measure_name)
      return nil if system_category_key.nil? || measure_name_key.nil?

      return [system_category_key, measure_name_key]
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
        measure_name: measure[:measure_name]
      }
      BOSS.BOSS_logger.warn(
        "BOSS.ScenarioMeasureMapper: #{message} " \
        "(measure_id: #{warning[:measure_id].inspect}, " \
        "system_category_affected: #{warning[:system_category_affected].inspect}, " \
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
