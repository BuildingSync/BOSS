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

  describe 'map_measure with conditional_arguments should' do
    def conditional_step(measure_dir_name, rules, arguments = { __SKIP__: false })
      { measure_dir_name:, arguments:, conditional_arguments: rules }
    end

    def conditional_mapping(steps, system_category_affected: 'Lighting', technology_category_element_name: 'LightingImprovements')
      {
        system_category_affected:,
        technology_category_element_name:,
        measure_name: 'Conditional measure',
        steps:
      }
    end

    def conditional_mapper(mappings)
      with_map_file(JSON.generate(mappings:)) { |map_path| yield BOSS::ScenarioMeasureMapper.new(map_path) }
    end

    let(:conditional_measure) { lighting_measure(measure_name: 'Conditional measure') }
    let(:rules) do
      [
        { when: { building_type: ['SmallOffice', 'MediumOffice'] }, arguments: { space_type: 'Office' } },
        { when: { building_type: 'SmallOffice', hvac_system_type: 'PSZ-HP' }, arguments: { space_type: 'Small HP office', heat_pump: true } },
        { when: { hvac_system_type: 'PSZ-HP' }, arguments: { lpd: 0, enabled: false } }
      ]
    end

    it 'include matching arguments and exclude non-matching ones' do
      conditional_mapper([conditional_mapping([conditional_step('Conditional', rules, { __SKIP__: false, lpd: 0.6 })])]) do |map_mapper|
        cases = {
          nil => { __SKIP__: false, lpd: 0.6 },
          { building_type: 'MediumOffice' } => { __SKIP__: false, lpd: 0.6, space_type: 'Office' },
          { building_type: ' smalloffice ', hvac_system_type: 'psz-hp', extra: 'ignored' } =>
            { __SKIP__: false, lpd: 0, space_type: 'Small HP office', heat_pump: true, enabled: false },
          { building_type: 'SmallOffice', hvac_system_type: 'PSZ-AC with gas unit heaters' } =>
            { __SKIP__: false, lpd: 0.6, space_type: 'Office' },
          { building_type: 'RetailStandalone', hvac_system_type: 'PSZ-HP' } => { __SKIP__: false, lpd: 0, enabled: false },
          { building_type: nil, hvac_system_type: '' } => { __SKIP__: false, lpd: 0.6 },
          { building_type: :SmallOffice } => { __SKIP__: false, lpd: 0.6 }
        }

        cases.each do |context, expected_arguments|
          result = map_mapper.map_measure(conditional_measure, context:)
          expect(result).to eq(measure_id: 'Measure1', steps: [{ measure_dir_name: 'Conditional', arguments: expected_arguments }], warnings: [])
        end
        expect(map_mapper.map_measure(conditional_measure)[:steps].first[:arguments]).to eq(__SKIP__: false, lpd: 0.6)
      end
    end

    it 'apply rules per step, keep step order, and drop metadata' do
      steps = [
        conditional_step('First', [{ when: { building_type: 'SmallOffice' }, arguments: { first: 1 } }]),
        conditional_step('Second', []),
        conditional_step('Third', [{ when: { building_type: 'LargeOffice' }, arguments: { third: 'x' } }])
      ]

      conditional_mapper([conditional_mapping(steps)]) do |map_mapper|
        result = map_mapper.map_measure(conditional_measure, context: { building_type: 'SmallOffice' })

        expect(result[:steps]).to eq [
          { measure_dir_name: 'First', arguments: { __SKIP__: false, first: 1 } },
          { measure_dir_name: 'Second', arguments: { __SKIP__: false } },
          { measure_dir_name: 'Third', arguments: { __SKIP__: false } }
        ]
      end
    end

    it 'not mutate inputs or leak state between calls' do
      conditional_mapper([conditional_mapping([conditional_step('Conditional', rules)])]) do |map_mapper|
        context = { building_type: 'SmallOffice', hvac_system_type: 'PSZ-HP' }
        context_before = Marshal.load(Marshal.dump(context))

        first = map_mapper.map_measure(conditional_measure, context:)
        first[:steps].first[:arguments][:space_type] << ' changed'
        first[:steps].first[:arguments][:extra] = 1

        expect(context).to eq context_before
        expect(map_mapper.map_measure(conditional_measure, context:)[:steps].first[:arguments][:space_type]).to eq 'Small HP office'
        expect(map_mapper.map_measure(conditional_measure, context: { building_type: 'LargeOffice' })[:steps].first[:arguments]).to eq(__SKIP__: false)
      end
    end

    it 'raise ArgumentError when context is not a Hash' do
      expect { mapper.map_measure(lighting_measure, context: 'SmallOffice') }.to raise_error(ArgumentError, /context must be a Hash/)
    end

    it 'treat mappings with the same defaults but different rules as different mappings' do
      wall = conditional_mapping(
        [conditional_step('Shared', [{ when: { building_type: 'SmallOffice' }, arguments: { wall: true } }])],
        system_category_affected: 'Wall', technology_category_element_name: 'BuildingEnvelopeModifications'
      )
      roof = conditional_mapping(
        [conditional_step('Shared', [{ when: { building_type: 'LargeOffice' }, arguments: { roof: true } }])],
        system_category_affected: 'Roof', technology_category_element_name: 'BuildingEnvelopeModifications'
      )
      envelope_measure = { measure_id: 'M', technology_category_element_name: 'BuildingEnvelopeModifications', measure_name: 'Conditional measure' }

      conditional_mapper([wall, roof, wall]) do |map_mapper|
        ambiguous = map_mapper.map_measure(envelope_measure, context: { building_type: 'MediumOffice' })
        resolved = map_mapper.map_measure(envelope_measure.merge(system_category_affected: 'Roof'), context: { building_type: 'LargeOffice' })

        expect(ambiguous[:warnings].map { |warning| warning[:code] }).to eq [:ambiguous_technology_category_mapping]
        expect(resolved[:steps]).to eq [{ measure_dir_name: 'Shared', arguments: { __SKIP__: false, roof: true } }]
      end
    end

    it 'match context derived from the reader for example-smalloffice-level1' do
      xml_path = mapper_fixture_path('v2.7.0', 'example-smalloffice-level1.xml')
      doc = REXML::Document.new(File.read(xml_path), ignore_whitespace_nodes: :all)
      reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      allow(BOSS.BOSS_logger).to receive(:info)
      building_type, = reader.get_building_type_and_bar_division_method
      context = { building_type:, hvac_system_type: reader.get_principal_HVAC_system_type }
      expect(context).to eq(building_type: 'SmallOffice', hvac_system_type: 'PSZ-HP')

      conditional_mapper([conditional_mapping([conditional_step('Conditional', rules)])]) do |map_mapper|
        expect(map_mapper.map_measure(conditional_measure, context:)[:steps].first[:arguments])
          .to eq(__SKIP__: false, space_type: 'Small HP office', heat_pump: true, lpd: 0, enabled: false)
      end
    end

    it 'keep building_151 results unchanged when context is supplied' do
      context = { building_type: 'RetailStandalone', hvac_system_type: 'VAV chiller with gas boiler reheat' }
      building_151_measures.each_value do |measure|
        expect(mapper.map_measure(measure, context:)).to eq mapper.map_measure(measure)
      end
    end
  end

  describe 'map_package_scenario should' do
    def fixture_reader(file_name)
      doc = REXML::Document.new(File.read(mapper_fixture_path('v2.7.0', file_name)), ignore_whitespace_nodes: :all)
      BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
    end

    def package_scenario(measure_ids)
      {
        scenario_id: 'ScenarioA',
        scenario_name: 'Package A',
        report_id: 'ReportA',
        scenario_type: :package_of_measures,
        package_id: 'PackageA',
        measure_ids:
      }
    end

    let(:scenario_context) { { report_id: 'ReportA', scenario_id: 'ScenarioA', package_id: 'PackageA' } }
    let(:led_step) { { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { __SKIP__: false, lpd: 0.6 } } }
    let(:measures) do
      {
        'Mapped' => lighting_measure(measure_id: 'Mapped'),
        'Unmapped' => lighting_measure(measure_id: 'Unmapped', measure_name: 'Not a mapped measure')
      }
    end

    it 'mark building_151 scenarios writable or skipped' do
      reader = fixture_reader('building_151.xml')
      all_measures = reader.get_measures

      results = reader.get_package_measure_scenarios.map { |scenario| mapper.map_package_scenario(scenario, all_measures) }

      expect(results.length).to eq 16
      skipped = results.select { |result| result[:status] == :skipped }
      expect(skipped.map { |result| result[:scenario_id] }).to eq ['Scenario4', 'Scenario5', 'Scenario6', 'Scenario18']
      expect(results.count { |result| result[:status] == :writable }).to eq 12
      skipped.each do |result|
        expect(result[:steps]).to eq []
        expect(result[:skipped_measure_ids]).to eq [result[:scenario_id].sub('Scenario', 'Measure')]
        expect(result[:warnings].map { |warning| warning[:code] }).to eq [:unmapped_measure, :package_has_no_mapped_measures]
      end
      expect(results.first).to eq(
        scenario_id: 'Scenario1',
        scenario_name: 'LED Only',
        report_id: 'Report1',
        package_id: 'PackageOfMeasures1',
        status: :writable,
        steps: [led_step],
        skipped_measure_ids: [],
        warnings: []
      )
    end

    it 'stay writable with mixed results and report skipped references in order' do
      result = mapper.map_package_scenario(package_scenario(['Unmapped', 'Mapped', 'Unknown', '']), measures)

      expect(result).to include(status: :writable, steps: [led_step], skipped_measure_ids: ['Unmapped', 'Unknown', ''])
      expect(result[:warnings].map { |warning| warning[:code] }).to eq [:unmapped_measure, :unresolved_measure_idref, :missing_measure_idref]
      expect(result[:warnings]).to all(include(scenario_context.merge(severity: :warning)))
      expect(result[:warnings][0]).to include(measure_id: 'Unmapped', measure_name: 'Not a mapped measure')
      expect(result[:warnings][1]).to include(measure_idref: 'Unknown', message: 'Package references an unknown measure ID.')
    end

    it 'skip zero-mapped scenarios with a summary warning' do
      [[], ['Unknown'], ['Unmapped']].each do |measure_ids|
        result = mapper.map_package_scenario(package_scenario(measure_ids), measures)

        expect(result).to include(status: :skipped, steps: [], skipped_measure_ids: measure_ids)
        expect(result[:warnings].last).to eq(
          code: :package_has_no_mapped_measures,
          severity: :warning,
          message: 'Package scenario has no mapped OpenStudio steps; scenario workflow will be skipped.',
          **scenario_context
        )
      end
    end

    it 'skip Golden Test File scenarios with incomplete measure metadata' do
      reader = fixture_reader('Golden Test File.xml')
      results = reader.get_package_measure_scenarios.map { |scenario| mapper.map_package_scenario(scenario, reader.get_measures) }

      expect(results).not_to be_empty
      results.each do |result|
        expect(result[:status]).to eq :skipped
        expect(result[:warnings].map { |warning| warning[:code] }.uniq).to eq [:measure_lookup_key_incomplete, :package_has_no_mapped_measures]
      end
    end

    it 'map every occurrence of repeated references' do
      result = mapper.map_package_scenario(package_scenario(['Mapped', 'Unknown', 'Mapped', 'Unknown']), measures)

      expect(result[:steps]).to eq [led_step, led_step]
      expect(result[:skipped_measure_ids]).to eq ['Unknown', 'Unknown']
      expect(result[:warnings].map { |warning| warning[:code] }).to eq [:unresolved_measure_idref, :unresolved_measure_idref]
    end

    it 'forward context to conditional mappings' do
      mapping = single_step_mapping('Lighting', 'LightingImprovements', 'Conditional measure', 'Conditional')
      mapping[:steps].first[:conditional_arguments] = [{ when: { building_type: 'SmallOffice' }, arguments: { office: true } }]
      conditional_measures = { 'C' => lighting_measure(measure_id: 'C', measure_name: 'Conditional measure') }

      with_map_file(JSON.generate(mappings: [mapping])) do |map_path|
        map_mapper = BOSS::ScenarioMeasureMapper.new(map_path)
        matched = map_mapper.map_package_scenario(package_scenario(['C', 'C']), conditional_measures, context: { building_type: 'SmallOffice' })
        unmatched = map_mapper.map_package_scenario(package_scenario(['C']), conditional_measures, context: nil)

        expect(matched[:steps]).to eq [{ measure_dir_name: 'Conditional', arguments: { __SKIP__: false, office: true } }] * 2
        expect(unmatched[:steps]).to eq [{ measure_dir_name: 'Conditional', arguments: { __SKIP__: false } }]
      end
    end

    it 'raise ArgumentError for invalid inputs' do
      expect { mapper.map_package_scenario(package_scenario([]), measures, context: 'x') }.to raise_error(ArgumentError, /context/)
      expect { mapper.map_package_scenario(nil, measures) }.to raise_error(ArgumentError, /scenario must be a Hash/)
      expect { mapper.map_package_scenario(package_scenario([]), []) }.to raise_error(ArgumentError, /measures must be a Hash/)
      expect { mapper.map_package_scenario(package_scenario([]).merge(scenario_type: :current_building), measures) }
        .to raise_error(ArgumentError, /package_of_measures/)
      expect { mapper.map_package_scenario(package_scenario(nil), measures) }.to raise_error(ArgumentError, /measure_ids/)
    end

    it 'log each new warning once without re-logging mapper warnings' do
      mapper.map_package_scenario(package_scenario(['Unmapped', 'Unknown']), measures)

      expect(BOSS.BOSS_logger).to have_received(:warn).with(/Measure has no OpenStudio mapping/).once
      expect(BOSS.BOSS_logger).to have_received(:warn).with(/unknown measure ID.*ScenarioA/).once
      expect(BOSS.BOSS_logger).to have_received(:warn).with(/will be skipped/).once
    end

    it 'not mutate inputs or share state between results' do
      scenario = package_scenario(['Mapped', 'Unknown'])
      scenario_before = Marshal.load(Marshal.dump(scenario))
      measures_before = Marshal.load(Marshal.dump(measures))

      first = mapper.map_package_scenario(scenario, measures)
      first[:steps].first[:arguments][:lpd] = 99.0
      first[:skipped_measure_ids].first << 'x'
      first[:scenario_id] << 'x'
      first[:warnings].first[:measure_idref] << 'x'

      expect(scenario).to eq scenario_before
      expect(measures).to eq measures_before
      second = mapper.map_package_scenario(scenario, measures)
      expect(second).to include(scenario_id: 'ScenarioA', steps: [led_step], skipped_measure_ids: ['Unknown'])
      expect(second[:warnings].first[:measure_idref]).to eq 'Unknown'
    end
  end

  describe 'initialize should' do
    it 'raise ArgumentError for malformed conditional_arguments' do
      invalid_rule_sets = {
        nil => /must be an array/,
        'rule' => /must be an array/,
        ['rule'] => /\[0\] must be an object/,
        [{ when: { building_type: 'A' }, arguments: { a: 1 }, unless: {} }] => /unknown keys/,
        [{ arguments: { a: 1 } }] => /when must be a non-empty object/,
        [{ when: {}, arguments: { a: 1 } }] => /when must be a non-empty object/,
        [{ when: { occupancy: 'Office' }, arguments: { a: 1 } }] => /unknown key 'occupancy'/,
        [{ when: { building_type: ' ' }, arguments: { a: 1 } }] => /when.building_type must be/,
        [{ when: { building_type: [] }, arguments: { a: 1 } }] => /when.building_type must be/,
        [{ when: { hvac_system_type: [1] }, arguments: { a: 1 } }] => /when.hvac_system_type must be/,
        [{ when: { building_type: 'A' } }] => /arguments must be a non-empty object/,
        [{ when: { building_type: 'A' }, arguments: {} }] => /arguments must be a non-empty object/,
        [{ when: { building_type: 'A' }, arguments: { a: nil } }] => /arguments.a must be a string, number, or boolean/,
        [{ when: { building_type: 'A' }, arguments: { a: [1] } }] => /arguments.a must be a string, number, or boolean/
      }

      invalid_rule_sets.each do |rule_set, message|
        mapping = single_step_mapping('Lighting', 'LightingImprovements', 'Bad', 'Bad')
        mapping[:steps].first[:conditional_arguments] = rule_set
        with_map_file(JSON.generate(mappings: [mapping])) do |map_path|
          expect { BOSS::ScenarioMeasureMapper.new(map_path) }
            .to raise_error(ArgumentError, /mappings\[0\]\.steps\[0\]\.conditional_arguments.*#{message.source}/)
        end
      end
    end

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
