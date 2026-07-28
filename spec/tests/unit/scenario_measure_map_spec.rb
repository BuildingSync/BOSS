# frozen_string_literal: true

require 'json'

SCENARIO_MEASURE_MAP_PATH = File.expand_path('../../../lib/BOSS/scenario_measure_map.json', __dir__)

RSpec.describe 'scenario_measure_map.json' do
  let(:scenario_measure_map) { JSON.parse(File.read(SCENARIO_MEASURE_MAP_PATH)) }
  let(:mappings) { scenario_measure_map.fetch('mappings') }

  it 'defines required mapping fields for each entry' do
    expect(scenario_measure_map.fetch('schema_version')).to eq '1.0'
    expect(mappings).not_to be_empty

    mappings.each do |mapping|
      expect(mapping.fetch('system_category_affected')).not_to be_empty
      expect(mapping.fetch('measure_name')).not_to be_empty
      expect(mapping.fetch('steps')).not_to be_empty

      mapping.fetch('steps').each do |step|
        expect(step.fetch('measure_dir_name')).not_to be_empty
        expect(step.fetch('arguments')).to be_a Hash
      end
    end
  end

  it 'uses OSW-shaped argument hashes without conditional mapping rules' do
    mappings.each do |mapping|
      mapping.fetch('steps').each do |step|
        expect(step.fetch('arguments')).to include('__SKIP__')
        expect(step.fetch('arguments')).not_to include('condition')
      end
    end
  end

  it 'covers the verified initial building_151 measure set' do
    expected_sources = [
      ['Air Distribution', 'Add or repair economizer'],
      ['Air Distribution', 'Install demand control ventilation'],
      ['Ceiling', 'Increase ceiling insulation'],
      ['General Controls and Operations', 'Upgrade operating protocols, calibration, and/or sequencing'],
      ['Lighting', 'Add occupancy sensors'],
      ['Lighting', 'Retrofit with light emitting diode technologies'],
      ['Plug Load', 'Install plug load controls'],
      ['Refrigeration', 'Replace ice/refrigeration equipment with high efficiency units'],
      ['Roof', 'Increase roof insulation'],
      ['Wall', 'Air seal envelope'],
      ['Wall', 'Increase wall insulation'],
      ['Wall', 'Insulate thermal bypasses']
    ]

    actual_sources = mappings.map do |mapping|
      [mapping.fetch('system_category_affected'), mapping.fetch('measure_name')]
    end

    expect(actual_sources).to eq expected_sources
  end
end
