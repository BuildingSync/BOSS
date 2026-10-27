# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'json'
require 'tempfile'
require 'BOSS/constants'
require 'BOSS/buildingsync_reader/buildingsync_reader'
require 'BOSS/scenario_measure_mapper'

RSpec.describe 'ScenarioMeasureMapper' do
  def mapper_fixture_path(*parts)
    File.expand_path(File.join('../../files', *parts), __dir__)
  end

  def fixture_measures(file_name)
    xml_path = mapper_fixture_path('v2.7.0', file_name)
    doc = REXML::Document.new(File.read(xml_path), ignore_whitespace_nodes: :all)
    BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1).get_measures
  end

  def building_151_measures
    fixture_measures('building_151.xml')
  end

  def single_step_mapping(system_category_affected, technology_category_element_name, measure_name, measure_dir_name)
    {
      system_category_affected:,
      technology_category_element_name:,
      measure_name:,
      steps: [{ measure_dir_name:, arguments: { __SKIP__: false } }]
    }
  end

  def with_map_file(content)
    file = Tempfile.new(['scenario_measure_map', '.json'])
    file.write(content)
    file.close
    yield file.path
  ensure
    file&.unlink
  end

  def lighting_measure(overrides = {})
    {
      measure_id: 'Measure1',
      system_category_affected: 'Lighting',
      technology_category_element_name: 'LightingImprovements',
      measure_name: 'Retrofit with light emitting diode technologies'
    }.merge(overrides)
  end

  # Silence mapper warning logs; the structured return value is what these tests check.
  before { allow(BOSS.BOSS_logger).to receive(:warn) }

  let(:mapper) { BOSS::ScenarioMeasureMapper.new }

  describe 'map_measure should' do
    it 'map building_151 Measure1 to the LED lighting step' do
      # Set Up
      measure = building_151_measures.fetch('Measure1')
      expected = JSON.parse(
        File.read(mapper_fixture_path('v2.7.0', 'expected', 'building_151_scenario1_resolved_measures.json')),
        symbolize_names: true
      )
      expect(measure).to eq expected[:resolved_measures].first

      # Action
      result = mapper.map_measure(measure)

      # Assert
      expect(result).to eq(
        measure_id: 'Measure1',
        steps: [
          { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { __SKIP__: false, lpd: 0.6 } }
        ],
        warnings: []
      )
    end

    it 'map the verified building_151 measures and warn for the deferred ones' do
      # Set Up
      measures = building_151_measures

      # Action
      results = measures.transform_values { |measure| mapper.map_measure(measure) }

      # Assert
      expect(measures.length).to eq 16
      mapped_ids = results.select { |_id, result| result[:steps].any? }.keys
      unmapped_ids = results.select { |_id, result| result[:steps].empty? }.keys
      expect(mapped_ids.length).to eq 12
      expect(unmapped_ids).to contain_exactly('Measure4', 'Measure5', 'Measure6', 'Measure18')

      results.each_value do |result|
        if result[:steps].any?
          expect(result[:warnings]).to eq []
        else
          expect(result[:warnings].map { |warning| warning[:code] }).to eq [:unmapped_measure]
        end
      end

      boiler_warning = results.fetch('Measure18')[:warnings].first
      expect(boiler_warning).to eq(
        code: :unmapped_measure,
        severity: :warning,
        message: 'Measure has no OpenStudio mapping.',
        measure_id: 'Measure18',
        system_category_affected: 'Heating System',
        technology_category_element_name: 'BoilerPlantImprovements',
        measure_name: 'Replace boiler'
      )
    end

    it 'normalize case and whitespace in lookup keys' do
      # Set Up
      messy_measure = lighting_measure(
        system_category_affected: '  LIGHTING ',
        measure_name: 'retrofit  with light Emitting diode technologies '
      )

      # Action
      result = mapper.map_measure(messy_measure)

      # Assert
      expect(result[:steps]).to eq mapper.map_measure(lighting_measure)[:steps]
      expect(result[:warnings]).to eq []
    end

    it 'warn without raising when MeasureName or both categories are missing' do
      # Set Up
      incomplete_measures = [
        lighting_measure(measure_name: nil),
        lighting_measure(system_category_affected: nil, measure_name: ' '),
        lighting_measure(system_category_affected: '  ', technology_category_element_name: nil)
      ]

      incomplete_measures.each do |measure|
        # Action
        result = mapper.map_measure(measure)

        # Assert
        expect(result[:steps]).to eq []
        expect(result[:warnings].map { |warning| warning[:code] }).to eq [:measure_lookup_key_incomplete]
        expect(result[:warnings].first).to include(measure.merge(severity: :warning))
      end
    end

    it 'map by technology category plus MeasureName when SystemCategoryAffected is missing' do
      # Set Up
      expected_steps = mapper.map_measure(lighting_measure)[:steps]
      technology_category_measures = [nil, '', '  '].map { |blank_category| lighting_measure(system_category_affected: blank_category) }
      technology_category_measures << lighting_measure(
        system_category_affected: nil,
        technology_category_element_name: ' lightingimprovements ',
        measure_name: 'Retrofit with  light emitting diode technologies'
      )

      technology_category_measures.each do |measure|
        # Action and Assert
        expect(mapper.map_measure(measure)).to eq(measure_id: 'Measure1', steps: expected_steps, warnings: [])
      end
    end

    it 'map building_151 measures the same way by either category lookup' do
      building_151_measures.each_value do |measure|
        # Action
        full_result = mapper.map_measure(measure)
        category_only_results = [
          mapper.map_measure(measure.merge(system_category_affected: nil)),
          mapper.map_measure(measure.merge(technology_category_element_name: nil)),
          mapper.map_measure(measure.merge(technology_category_element_name: 'UnmappedTechnology'))
        ]

        # Assert
        category_only_results.each do |result|
          if full_result[:steps].any?
            expect(result).to eq full_result
          else
            expect(result[:warnings].map { |warning| warning[:code] }).to eq [:unmapped_measure]
          end
        end
      end
    end

    it 'map 179D_Example_Building measures that have no SystemCategoryAffected' do
      # Set Up
      measures = fixture_measures('179D_Example_Building.xml')
      expect(measures.values.map { |measure| measure[:system_category_affected] }).to all(be_nil)

      # Action
      results = measures.transform_values { |measure| mapper.map_measure(measure) }

      # Assert
      expect(results.fetch('MeasureType-45099320')[:steps]).to eq [
        { measure_dir_name: 'ReduceSpaceInfiltrationByPercentage', arguments: { __SKIP__: false, space_infiltration_reduction_percent: 30.0 } }
      ]
      expect(results.fetch('MeasureType-45099340')[:steps]).to eq [
        { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { __SKIP__: false, lpd: 0.6 } }
      ]
      ['MeasureType-45099360', 'MeasureType-45099380'].each do |measure_id|
        expect(results.fetch(measure_id)[:steps]).to eq []
        expect(results.fetch(measure_id)[:warnings].first).to include(code: :unmapped_measure, technology_category_element_name: 'ServiceHotWaterSystems')
      end
    end

    it 'prefer technology category lookup over SystemCategoryAffected lookup' do
      # Set Up
      map_json = JSON.generate(
        mappings: [
          single_step_mapping('Lighting', 'OtherTechnology', 'Shared measure', 'SystemCategoryMatch'),
          single_step_mapping('Other System', 'LightingImprovements', 'Shared measure', 'TechnologyCategoryMatch')
        ]
      )

      with_map_file(map_json) do |map_path|
        # Action
        result = BOSS::ScenarioMeasureMapper.new(map_path).map_measure(lighting_measure(measure_name: 'Shared measure'))

        # Assert
        expect(result[:steps].map { |step| step[:measure_dir_name] }).to eq ['TechnologyCategoryMatch']
        expect(result[:warnings]).to eq []
      end
    end

    it 'map Fenestration air sealing by technology category and leave cross-category protocol measures unmapped' do
      # Set Up
      fenestration_measure = fixture_measures('Example_ASHRAE_L2_Report_-_with_Energy_Use_Data.xml').fetch('MeasureType-45035260')
      expect(fenestration_measure).to include(system_category_affected: 'Fenestration', technology_category_element_name: 'BuildingEnvelopeModifications')
      homes_measures = fixture_measures('Example_HOMES_Template_Building.xml')
      protocol_measures = homes_measures.values_at('MeasureType-45139460', 'MeasureType-45139560')
      expect(protocol_measures.map { |measure| measure[:system_category_affected] }).to eq ['Other HVAC', 'Domestic Hot Water']
      expect(protocol_measures.map { |measure| measure[:technology_category_element_name] }).to eq ['BuildingAutomationSystems', 'WaterAndSewerConservationSystems']

      # Action
      fenestration_result = mapper.map_measure(fenestration_measure)
      protocol_results = protocol_measures.map { |measure| mapper.map_measure(measure) }

      # Assert
      expect(fenestration_result[:steps]).to eq mapper.map_measure(building_151_measures.fetch('Measure3'))[:steps]
      expect(fenestration_result[:warnings]).to eq []
      protocol_results.each do |result|
        expect(result[:steps]).to eq []
        expect(result[:warnings].map { |warning| warning[:code] }).to eq [:unmapped_measure]
      end
    end

    it 'fall back to SystemCategoryAffected when the technology category lookup is ambiguous' do
      # Set Up
      map_json = JSON.generate(
        mappings: [
          single_step_mapping('Wall', 'BuildingEnvelopeModifications', 'Air seal envelope', 'WallAirSeal'),
          single_step_mapping('Roof', 'BuildingEnvelopeModifications', 'Air seal envelope', 'RoofAirSeal'),
          single_step_mapping('Wall', 'BuildingEnvelopeModifications', 'Shared steps', 'SameStep'),
          single_step_mapping('Roof', 'BuildingEnvelopeModifications', 'Shared steps', 'SameStep')
        ]
      )
      envelope_measure = { measure_id: 'Measure3', technology_category_element_name: 'BuildingEnvelopeModifications', measure_name: 'Air seal envelope' }

      with_map_file(map_json) do |map_path|
        map_path_mapper = BOSS::ScenarioMeasureMapper.new(map_path)

        # Action
        ambiguous_results = [nil, 'Fenestration'].map { |category| map_path_mapper.map_measure(envelope_measure.merge(system_category_affected: category)) }
        same_steps_result = map_path_mapper.map_measure(envelope_measure.merge(measure_name: 'Shared steps'))
        categorized_result = map_path_mapper.map_measure(envelope_measure.merge(system_category_affected: 'Roof'))

        # Assert
        ambiguous_results.each do |result|
          expect(result[:steps]).to eq []
          expect(result[:warnings].map { |warning| warning[:code] }).to eq [:ambiguous_technology_category_mapping]
        end
        expect(same_steps_result).to include(steps: [{ measure_dir_name: 'SameStep', arguments: { __SKIP__: false } }], warnings: [])
        expect(categorized_result[:steps].map { |step| step[:measure_dir_name] }).to eq ['RoofAirSeal']
      end
    end

    it 'log a warning for unmapped measures' do
      # Action
      mapper.map_measure(lighting_measure(measure_name: 'Not a mapped measure'))

      # Assert
      expect(BOSS.BOSS_logger).to have_received(:warn).with(/Measure has no OpenStudio mapping/).once
    end

    it 'not mutate the input measure or the loaded mapping' do
      # Set Up
      measure = lighting_measure
      measure_before = Marshal.load(Marshal.dump(measure))

      # Action
      first_result = mapper.map_measure(measure)
      first_result[:steps].first[:arguments][:lpd] = 99.0
      first_result[:steps] << { measure_dir_name: 'Extra', arguments: {} }
      second_result = mapper.map_measure(measure)

      # Assert
      expect(measure).to eq measure_before
      expect(second_result[:steps]).to eq [
        { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { __SKIP__: false, lpd: 0.6 } }
      ]
    end

    it 'preserve step order for multi-step mappings' do
      # Set Up
      map_json = JSON.generate(
        mappings: [
          {
            system_category_affected: 'Lighting',
            measure_name: 'Two step measure',
            steps: [
              { measure_dir_name: 'SecondAlphabetically', arguments: { __SKIP__: false } },
              { measure_dir_name: 'AFirstAlphabetically', arguments: { __SKIP__: false } }
            ]
          }
        ]
      )

      with_map_file(map_json) do |map_path|
        # Action
        result = BOSS::ScenarioMeasureMapper.new(map_path).map_measure(lighting_measure(measure_name: 'Two step measure'))

        # Assert
        expect(result[:steps].map { |step| step[:measure_dir_name] }).to eq ['SecondAlphabetically', 'AFirstAlphabetically']
      end
    end
  end

  describe 'initialize should' do
    it 'raise ArgumentError when the map file does not exist' do
      expect { BOSS::ScenarioMeasureMapper.new(mapper_fixture_path('missing_map.json')) }
        .to raise_error(ArgumentError, /does not exist/)
    end

    it 'raise ArgumentError when the map file is not valid JSON' do
      with_map_file('{ not json') do |map_path|
        expect { BOSS::ScenarioMeasureMapper.new(map_path) }.to raise_error(ArgumentError, /not valid JSON/)
      end
    end

    it 'raise ArgumentError when the map file has no mappings array' do
      with_map_file(JSON.generate(schema_version: '1.0')) do |map_path|
        expect { BOSS::ScenarioMeasureMapper.new(map_path) }.to raise_error(ArgumentError, /'mappings' array/)
      end
    end
  end
end
