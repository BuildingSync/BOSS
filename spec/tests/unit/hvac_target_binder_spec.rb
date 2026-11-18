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

  it 'binds any premises to explicit zone names as a JSON array' do
    premises = [{ type: 'ThermalZone', id: 'TZ-1' }]
    binding = binder.bind(match_result(premises), operation: 'replace', standards_template: '90.1-2019',
                                                  zone_names: ['Office, East', 'Core', 'Core'])
    expect(binding.status).to eq(:bound)
    expect(binding.step[:arguments]).to eq(
      topology_measure: 'hvac_ptac', operation: 'replace', zone_scope: 'explicit_zone_names',
      zone_names_json: '["Office, East","Core"]', standards_template: '90.1-2019'
    )
  end

  it 'rejects empty or blank explicit zone names' do
    result = match_result([{ type: 'Building', id: 'B-1' }])
    [[], [''], [nil]].each do |names|
      expect { binder.bind(result, operation: 'create', standards_template: '90.1-2019', zone_names: names) }
        .to raise_error(ArgumentError, /zone_names/)
    end
  end

  it 'forwards selector measure arguments as topology_arguments_json' do
    result = match_result([{ type: 'Building', id: 'B-1' }], measure: 'hvac_packaged_rooftop_heat_pump')
    result.measure_arguments = { 'supplemental_heating_fuel' => 'NaturalGas' }
    binding = binder.bind(result, operation: 'create', standards_template: '90.1-2019')
    expect(binding.step[:arguments][:topology_arguments_json]).to eq('{"supplemental_heating_fuel":"NaturalGas"}')
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
    expect { binder.bind(result, operation: 'create', standards_template: 'DEER 2017') }
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
    expect(names).to eq(['topology_measure', 'operation', 'zone_scope', 'zone_names_json', 'standards_template',
                         'topology_arguments_json'])
    scopes = doc.get_elements("measure/arguments/argument[name='zone_scope']/choices/choice/value").map(&:text)
    expect(scopes).to eq(['all_model_zones', 'explicit_zone_names'])
    topologies = doc.get_elements("measure/arguments/argument[name='topology_measure']/choices/choice/value").map(&:text)
    expect(topologies).to include('hvac_ptac', 'hvac_doas', 'hvac_vav_hw_reheat')
  end

  describe '#bind_modifier' do
    let(:efficiency) { { efficiency_metric: 'dx_cooling_cop', efficiency_value: 4.0 } }

    it 'binds whole-building premises to all matching objects' do
      binding = binder.bind_modifier(modifier_measure: 'modify_existing_hvac_equipment_efficiencies',
                                     modifier_arguments: efficiency, premises: [{ type: 'Building', id: 'B-1' }])
      expect(binding.status).to eq(:bound)
      expect(binding.step).to eq(
        measure_dir_name: 'apply_hvac_modifier_to_object_scope',
        arguments: { modifier_measure: 'modify_existing_hvac_equipment_efficiencies', object_scope: 'all_matching_objects',
                     modifier_arguments_json: '{"efficiency_metric":"dx_cooling_cop","efficiency_value":4.0}' }
      )
    end

    it 'binds any premises to explicit object names' do
      binding = binder.bind_modifier(modifier_measure: 'modify_existing_heat_recovery',
                                     modifier_arguments: { effectiveness: 0.7 },
                                     premises: [{ type: 'ThermalZone', id: 'TZ-1' }], object_names: ['ERV 1', 'ERV 1'])
      expect(binding.step[:arguments]).to include(object_scope: 'explicit_object_names', object_names_json: '["ERV 1"]')
    end

    it 'returns missing input for non-whole-building premises or unscoped plant loops' do
      zone = binder.bind_modifier(modifier_measure: 'modify_existing_heat_recovery', modifier_arguments: {},
                                  premises: [{ type: 'ThermalZone', id: 'TZ-1' }])
      expect(zone.status).to eq(:missing_input)
      expect(zone.messages.first).to include('ThermalZone TZ-1')
      loops = binder.bind_modifier(modifier_measure: 'modify_existing_plant_loop_temperatures',
                                   modifier_arguments: { design_loop_exit_temperature_c: 60.0 },
                                   premises: [{ type: 'Building', id: 'B-1' }])
      expect(loops.status).to eq(:missing_input)
      heating = binder.bind_modifier(modifier_measure: 'modify_existing_plant_loop_temperatures',
                                     modifier_arguments: { design_loop_exit_temperature_c: 60.0 },
                                     premises: [{ type: 'Building', id: 'B-1' }], plant_loop_type: 'Heating')
      expect(heating.step[:arguments]).to include(object_scope: 'all_matching_objects', plant_loop_type: 'Heating')
    end

    it 'rejects unsupported modifiers, target-name arguments, and bad inputs' do
      building = [{ type: 'Building', id: 'B-1' }]
      expect { binder.bind_modifier(modifier_measure: 'hvac_ptac', modifier_arguments: {}, premises: building) }
        .to raise_error(ArgumentError, /modifier_measure/)
      expect do
        binder.bind_modifier(modifier_measure: 'modify_existing_heat_recovery',
                             modifier_arguments: { 'target_heat_exchanger_names' => 'X' }, premises: building)
      end.to raise_error(ArgumentError, /target_heat_exchanger_names/)
      expect do
        binder.bind_modifier(modifier_measure: 'modify_existing_heat_recovery', modifier_arguments: {},
                             premises: building, object_names: [''])
      end.to raise_error(ArgumentError, /object_names/)
      expect do
        binder.bind_modifier(modifier_measure: 'modify_existing_plant_loop_temperatures', modifier_arguments: {},
                             premises: building, plant_loop_type: 'Steam')
      end.to raise_error(ArgumentError, /plant_loop_type/)
    end

    it 'matches the modifier binding measure arguments in the configured measure source' do
      dirs = BOSS::ExternalMeasureRepoManager.new.resolved_measure_directories(include_scenario_only: true)
      xml_path = dirs.map { |dir| File.join(dir, described_class::MODIFIER_BINDING_MEASURE, 'measure.xml') }
                     .find { |p| File.file?(p) }
      skip 'apply_hvac_modifier_to_object_scope is not in the configured measure source' if xml_path.nil?

      doc = REXML::Document.new(File.read(xml_path))
      names = doc.get_elements('measure/arguments/argument/name').map(&:text)
      expect(names).to eq(['modifier_measure', 'object_scope', 'object_names_json', 'plant_loop_type', 'modifier_arguments_json'])
      choices = ->(arg) { doc.get_elements("measure/arguments/argument[name='#{arg}']/choices/choice/value").map(&:text) }
      expect(choices.call('modifier_measure')).to match_array(described_class::MODIFIER_TARGETS.keys)
      expect(choices.call('object_scope')).to eq(['all_matching_objects', 'explicit_object_names'])
      expect(choices.call('plant_loop_type')).to include(*described_class::PLANT_LOOP_TYPES)

      described_class::MODIFIER_TARGETS.each do |modifier, target_key|
        modifier_xml = File.join(File.dirname(xml_path, 2), modifier, 'measure.xml')
        modifier_args = REXML::Document.new(File.read(modifier_xml)).get_elements('measure/arguments/argument/name').map(&:text)
        expect(modifier_args).to include(target_key)
      end
    end
  end
end
