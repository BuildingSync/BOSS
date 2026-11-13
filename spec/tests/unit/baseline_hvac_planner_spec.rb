# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'rexml/document'
require 'BOSS/baseline_hvac_planner'
require 'BOSS/boss_logger'
require 'BOSS/buildingsync_reader/buildingsync_reader'

RSpec.describe BOSS::BaselineHvacPlanner do
  building = [{ type: 'Building', id: 'B-1' }]
  result = lambda do |status: :match, measure: 'hvac_ptac', configuration: 'PTAC', group_key: [:delivery, 'D-1'], premises: building, messages: []|
    BOSS::HvacTopologySelector::Result.new(status:, configuration:, measure:, hvac_system_id: 'HVAC-1',
                                           record_ids: [], premises:, group_key:, messages:)
  end
  hvac_systems = REXML::Document.new('<HVACSystems/>').root

  def plan_for(results, systems, template = '90.1-2019')
    selector = instance_double(BOSS::HvacTopologySelector, select: results)
    described_class.new(selector:).plan(systems, template)
  end

  it 'plans whole-building create steps, ventilation last, then sizing' do
    doas = result.call(measure: 'hvac_doas', configuration: 'DOAS', group_key: [:other, 'O-1'])
    plan = plan_for([doas, result.call, result.call(group_key: [:delivery, 'D-1'])], hvac_systems, '90.1-2016')

    expect(plan.status).to eq(:topology)
    expect(plan.steps.map { |step| step[:measure_dir_name] }).to eq(
      ['apply_hvac_topology_to_zone_scope', 'apply_hvac_topology_to_zone_scope', 'apply_standard_hvac_sizing_and_efficiency']
    )
    expect(plan.steps.map { |step| step[:arguments][:topology_measure] }.compact).to eq(['hvac_ptac', 'hvac_doas'])
    expect(plan.steps.map { |step| step[:arguments][:operation] }.compact).to eq(['create', 'create'])
    expect(plan.steps.map { |step| step[:arguments][:standards_template] }.uniq).to eq(['90.1-2016'])
  end

  {
    'no HVACSystems' => [[], nil, '90.1-2019', /No HVACSystems/],
    'an unsupported template' => [[], :systems, '90.1-2010', /Template '90.1-2010'/],
    'family-only data' => [[{ status: :missing_input, messages: ['Only family-level data'] }], :systems, '90.1-2019',
                           /missing_input.*family-level/],
    'two conditioning configurations' => [[{}, { measure: 'hvac_pthp', group_key: [:delivery, 'D-2'] }], :systems, '90.1-2019',
                                          /one conditioning configuration, found 2/],
    'ventilation on air-loop HVAC' => [[{ measure: 'hvac_warm_air_furnace', configuration: 'Furnace' },
                                        { measure: 'hvac_doas', configuration: 'DOAS', group_key: [:other, 'O-1'] }],
                                       :systems, '90.1-2019', /DOAS cannot be added.*Furnace/],
    'zone-linked premises' => [[{ premises: [{ type: 'ThermalZone', id: 'TZ-1' }] }], :systems, '90.1-2019',
                               /only whole-building premises/]
  }.each do |label, (specs, systems, template, message)|
    it "falls back for #{label}" do
      plan = plan_for(specs.map { |spec| result.call(**spec) }, systems && hvac_systems, template)

      expect(plan.status).to eq(:fallback)
      expect(plan.steps).to be_empty
      expect(plan.messages.join("\n")).to match(message)
    end
  end

  it 'plans a building-linked PTAC from BuildingSync XML' do
    xml = '<HVACSystems><HVACSystem ID="HVAC-1"><HeatingAndCoolingSystems>' \
          '<HeatingSources><HeatingSource ID="HS-1"><HeatingSourceType><ElectricResistance/></HeatingSourceType></HeatingSource></HeatingSources>' \
          '<CoolingSources><CoolingSource ID="CS-1"><CoolingSourceType><DX><DXSystemType>Packaged terminal air conditioner (PTAC)</DXSystemType>' \
          '<CondenserPlantIDs><CondenserPlantID IDref="CN-AIR"/></CondenserPlantIDs></DX></CoolingSourceType></CoolingSource></CoolingSources>' \
          '<Deliveries><Delivery ID="D-1"><LinkedPremises><Building><LinkedBuildingID IDref="B-1"/></Building></LinkedPremises>' \
          '<DeliveryType><ZoneEquipment/></DeliveryType><HeatingSourceID IDref="HS-1"/><CoolingSourceID IDref="CS-1"/></Delivery></Deliveries>' \
          '</HeatingAndCoolingSystems><Plants><CondenserPlants><CondenserPlant ID="CN-AIR"><AirCooled/></CondenserPlant></CondenserPlants>' \
          '</Plants></HVACSystem></HVACSystems>'
    plan = described_class.new.plan(REXML::Document.new(xml).root, '90.1-2019')

    expect(plan.status).to eq(:topology), plan.messages.join("\n")
    expect(plan.steps.first[:arguments][:topology_measure]).to eq('hvac_ptac')
  end

  sectioned = REXML::Document.new(
    '<BuildingSync><Building ID="B-1"><Sections>' \
    '<Section ID="S-1"><SectionType>Space function</SectionType></Section>' \
    '<Section ID="S-2"><SectionType>Space function</SectionType></Section>' \
    '</Sections></Building><HVACSystems/></BuildingSync>'
  )
  sectioned_systems = REXML::XPath.first(sectioned, '//HVACSystems')
  section = ->(id) { [{ type: 'Section', id: }] }

  it 'merges same-configuration deliveries whose Section links cover the building' do
    results = [result.call(premises: section.call('S-1')),
               result.call(premises: section.call('S-2'), group_key: [:delivery, 'D-2'])]
    plan = plan_for(results, sectioned_systems)

    expect(plan.status).to eq(:topology), plan.messages.join("\n")
    expect(plan.steps.map { |step| step[:arguments][:topology_measure] }.compact).to eq(['hvac_ptac'])
    expect(plan.steps.first[:arguments][:zone_scope]).to eq('all_model_zones')
  end

  it 'falls back when Section links leave part of the building unserved' do
    plan = plan_for([result.call(premises: section.call('S-1'))], sectioned_systems)

    expect(plan.status).to eq(:fallback)
    expect(plan.messages.join("\n")).to match(/Section S-1.*only whole-building premises/)
  end

  it 'keeps different measure arguments as separate configurations' do
    results = [['D-1', 'NaturalGas'], ['D-2', 'Electricity']].map do |id, fuel|
      result.call(measure: 'hvac_packaged_rooftop_heat_pump', group_key: [:delivery, id])
            .tap { |r| r.measure_arguments = { 'supplemental_heating_fuel' => fuel } }
    end
    plan = plan_for(results, hvac_systems)

    expect(plan.messages.join("\n")).to match(/one conditioning configuration, found 2/)
  end

  it 'plans topology HVAC for the 2012 small-office level 2 copy' do
    path = File.expand_path('../../files/v2.7.0/example-smalloffice-level2-built-2012.xml', __dir__)
    doc = REXML::Document.new(File.read(path), ignore_whitespace_nodes: :all)
    reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
    plan = described_class.new.plan(reader.get_hvac_systems_xml, reader.get_standard_template)

    expect(plan.status).to eq(:topology), plan.messages.join("\n")
    step = plan.steps.first[:arguments]
    expect(step).to include(topology_measure: 'hvac_packaged_rooftop_heat_pump', zone_scope: 'all_model_zones',
                            standards_template: '90.1-2013',
                            topology_arguments_json: '{"supplemental_heating_fuel":"NaturalGas"}')
    expect(plan.steps.last[:measure_dir_name]).to eq('apply_standard_hvac_sizing_and_efficiency')
  end
end
