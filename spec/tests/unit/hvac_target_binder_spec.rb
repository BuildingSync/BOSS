# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'json'
require 'BOSS/constants'
require 'BOSS/external_measure_repo_manager'
require 'BOSS/hvac_topology_selector'
require 'BOSS/hvac_target_binder'

RSpec.describe BOSS::HvacTargetBinder do
  def match_result(premises, measure: 'hvac_ptac')
    BOSS::HvacTopologySelector::Result.new(
      status: :match, configuration: 'Packaged Terminal Air Conditioner', measure: measure,
      hvac_system_id: 'HVAC-1', record_ids: ['D-1'], premises: premises, group_key: [:delivery, 'D-1'], messages: []
    )
  end

  let(:binder) { described_class.new }

  ['Building', 'Site', 'Facility'].each do |type|
    it "binds #{type} premises to all model zones through the runtime binding measure" do
      binding = binder.bind(match_result([{ type: type, id: "#{type}-1" }]),
                            operation: 'replace', standards_template: '90.1-2016')
      expect(binding.status).to eq(:bound)
      expect(binding.step).to eq(
        measure_dir_name: 'apply_hvac_topology_to_zone_scope',
        arguments: { topology_measure: 'hvac_ptac', operation: 'replace', zone_scope: 'all_model_zones',
                     standards_template: '90.1-2016' }
      )
    end
  end

  it 'returns missing input for zone or space premises instead of guessing names' do
    premises = [{ type: 'Building', id: 'B-1' }, { type: 'ThermalZone', id: 'TZ-1' }]
    binding = binder.bind(match_result(premises), operation: 'create', standards_template: '90.1-2019')
    expect(binding.status).to eq(:missing_input)
    expect(binding.step).to be_nil
    expect(binding.messages.first).to include('ThermalZone TZ-1')
  end

  it 'returns missing input when no premises are linked' do
    binding = binder.bind(match_result([]), operation: 'create', standards_template: '90.1-2019')
    expect(binding.status).to eq(:missing_input)
  end

  it 'passes non-match selector results through unchanged' do
    result = match_result([{ type: 'Building', id: 'B-1' }]).dup
    result.status = :mapping_gap
    result.messages = ['gap']
    binding = binder.bind(result, operation: 'create', standards_template: '90.1-2019')
    expect(binding).to have_attributes(status: :mapping_gap, step: nil, messages: ['gap'])
  end

  it 'rejects templates and operations the topology measures do not support' do
    result = match_result([{ type: 'Building', id: 'B-1' }])
    expect { binder.bind(result, operation: 'create', standards_template: 'DOE Ref Pre-1980') }
      .to raise_error(ArgumentError, /standards_template/)
    expect { binder.bind(result, operation: 'delete', standards_template: '90.1-2019') }
      .to raise_error(ArgumentError, /operation/)
  end

  it 'matches the binding measure arguments in the configured measure source' do
    dirs = BOSS::ExternalMeasureRepoManager.new.resolved_measure_directories(include_scenario_only: true)
    xml_path = dirs.map { |dir| File.join(dir, described_class::BINDING_MEASURE, 'measure.xml') }.find { |p| File.file?(p) }
    skip 'apply_hvac_topology_to_zone_scope is not in the configured measure source' if xml_path.nil?

    doc = REXML::Document.new(File.read(xml_path))
    names = doc.get_elements('measure/arguments/argument/name').map(&:text)
    expect(names).to eq(['topology_measure', 'operation', 'zone_scope', 'standards_template'])
    topologies = doc.get_elements("measure/arguments/argument[name='topology_measure']/choices/choice/value").map(&:text)
    expect(topologies).to include('hvac_ptac', 'hvac_doas', 'hvac_vav_hw_reheat')
  end
end
