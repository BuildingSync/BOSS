# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'rexml/document'
require 'BOSS/scenario_hvac_planner'

RSpec.describe BOSS::ScenarioHvacPlanner do
  fixture = File.expand_path('../../files/v2.7.0/example-smalloffice-level2-hvac-retrofits.xml', __dir__)
  template = 'DOE Ref 1980-2004'
  sizing = { measure_dir_name: 'apply_standard_hvac_sizing_and_efficiency', arguments: { standards_template: template },
             workflow_phase: 'hvac_equipment' }

  let(:doc) { REXML::Document.new(File.read(fixture), ignore_whitespace_nodes: :all) }
  let(:hvac_systems) { REXML::XPath.first(doc, "//*[local-name()='HVACSystems']") }

  def planner(doc, hvac_systems, template = 'DOE Ref 1980-2004')
    described_class.new(hvac_systems, doc, template)
  end

  def element(doc, id)
    REXML::XPath.first(doc, "//*[@ID='#{id}']")
  end

  it 'lists proposed HVACSystems named by measures' do
    expect(described_class.proposed_system_ids(hvac_systems))
      .to contain_exactly('HVACSystem-proposed-RTU', 'HVACSystem-proposed-COP')
  end

  it 'replaces HVAC with the alternative system topology' do
    result = planner(doc, hvac_systems).plan(measure_id: 'Measure-HVAC-RTU', measure_name: 'Replace package units')

    expect(result.status).to eq(:mapped), result.messages.join("\n")
    expect(result.steps.first).to eq(
      measure_dir_name: 'apply_hvac_topology_to_zone_scope', workflow_phase: 'hvac_equipment',
      arguments: { topology_measure: 'hvac_packaged_rooftop_ac', operation: 'replace', zone_scope: 'all_model_zones',
                   standards_template: template }
    )
    expect(result.steps.last).to eq(sizing)
  end

  it 'uses the configured retrofit template' do
    result = planner(doc, hvac_systems, '90.1-2019').plan(measure_id: 'Measure-HVAC-RTU')

    expect(result.steps.map { |step| step[:arguments][:standards_template] }).to all(eq('90.1-2019'))
  end

  it 'rejects an unsupported retrofit template' do
    result = planner(doc, hvac_systems, 'DEER 2017').plan(measure_id: 'Measure-HVAC-RTU')

    expect(result.status).to eq(:unmapped)
    expect(result.messages.join).to match(/DEER 2017/)
  end

  it 'rejects partial replacement of existing HVAC' do
    other = element(doc, 'HVACSystem-1').deep_clone
    other.attributes['ID'] = 'HVACSystem-2'
    hvac_systems.add_element(other)
    result = planner(doc, hvac_systems).plan(measure_id: 'Measure-HVAC-RTU')

    expect(result.status).to eq(:unmapped)
    expect(result.messages.join).to match(/HVACSystem-2 in place; partial HVAC replacement/)
  end

  it 'rejects an alternative system that serves only part of the building' do
    premises = REXML::XPath.first(element(doc, 'HVACSystem-proposed-RTU'), "*[local-name()='LinkedPremises']")
    premises.elements.delete_all('*')
    premises.add_element('ThermalZone').add_element('LinkedThermalZoneID', 'IDref' => 'TZ-1')
    result = planner(doc, hvac_systems).plan(measure_id: 'Measure-HVAC-RTU')

    expect(result.status).to eq(:unmapped)
    expect(result.messages.join).to match(/ThermalZone TZ-1.*only whole-building premises/)
  end

  it 'maps ModifiedSystem COPs to efficiency modifier steps' do
    result = planner(doc, hvac_systems).plan(measure_id: 'Measure-HVAC-COP')

    expect(result.status).to eq(:mapped), result.messages.join("\n")
    expect(result.steps.map { |step| step[:arguments][:modifier_arguments_json] }).to eq(
      ['{"efficiency_metric":"dx_cooling_cop","efficiency_value":3.5}',
       '{"efficiency_metric":"dx_heating_cop","efficiency_value":3.8}']
    )
    expect(result.steps).to all(include(measure_dir_name: 'apply_hvac_modifier_to_object_scope',
                                        workflow_phase: 'hvac_modifiers'))
    expect(result.steps.first[:arguments]).to include(modifier_measure: 'modify_existing_hvac_equipment_efficiencies',
                                                      object_scope: 'all_matching_objects')
  end

  it 'does not convert non-COP efficiency units' do
    units = REXML::XPath.first(element(doc, 'CoolingSource-proposed-COP'), "*[local-name()='AnnualCoolingEfficiencyUnits']")
    units.text = 'EER'
    result = planner(doc, hvac_systems).plan(measure_id: 'Measure-HVAC-COP')

    expect(result.status).to eq(:unmapped)
    expect(result.messages.join).to match(/units 'EER' are not COP/)
  end

  it 'replaces HVAC with VRF from the MeasureName' do
    result = planner(doc, hvac_systems).plan(measure_id: 'Measure-HVAC-VRF',
                                             measure_name: 'Install variable refrigerant flow system')

    expect(result.status).to eq(:mapped), result.messages.join("\n")
    expect(result.steps.first[:arguments]).to include(topology_measure: 'hvac_vrf', operation: 'replace')
    expect(result.steps.last).to eq(sizing)
  end

  it 'needs whole-building premises for a MeasureName topology' do
    REXML::XPath.first(element(doc, 'Measure-HVAC-VRF'), "*[local-name()='LinkedPremises']").remove
    result = planner(doc, hvac_systems).plan(measure_id: 'Measure-HVAC-VRF',
                                             measure_name: 'Install variable refrigerant flow system')

    expect(result.status).to eq(:unmapped)
    expect(result.messages.join).to match(/links no premises/)
  end

  it 'leaves other measures to the JSON map' do
    result = planner(doc, hvac_systems).plan(measure_id: 'Measure-LEDs',
                                             measure_name: 'Retrofit with light emitting diode technologies')

    expect(result.status).to eq(:not_hvac)
  end
end
