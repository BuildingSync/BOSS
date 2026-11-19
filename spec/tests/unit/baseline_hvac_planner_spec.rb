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
  result = lambda do |status: :match, measure: 'hvac_ptac', configuration: 'PTAC', group_key: [:delivery, 'D-1'], premises: building, messages: [], record_ids: []|
    BOSS::HvacTopologySelector::Result.new(status:, configuration:, measure:, hvac_system_id: 'HVAC-1',
                                           record_ids:, premises:, group_key:, messages:)
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
    'an unsupported template' => [[], :systems, 'DEER 2017', /Template 'DEER 2017'/],
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

  {
    'example-smalloffice-level2.xml' => 'DOE Ref 1980-2004',
    'example-smalloffice-level2-built-2012.xml' => '90.1-2013'
  }.each do |file_name, template|
    it "plans topology HVAC for #{file_name} with #{template}" do
      path = File.expand_path("../../files/v2.7.0/#{file_name}", __dir__)
      doc = REXML::Document.new(File.read(path), ignore_whitespace_nodes: :all)
      reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      plan = described_class.new.plan(reader.get_hvac_systems_xml, reader.get_standard_template)

      expect(plan.status).to eq(:topology), plan.messages.join("\n")
      step = plan.steps.first[:arguments]
      expect(step).to include(topology_measure: 'hvac_packaged_rooftop_heat_pump', zone_scope: 'all_model_zones',
                              standards_template: template,
                              topology_arguments_json: '{"supplemental_heating_fuel":"NaturalGas"}')
      expect(plan.steps.last).to eq(measure_dir_name: 'apply_standard_hvac_sizing_and_efficiency',
                                    arguments: { standards_template: template })
    end
  end

  describe 'exhaust air recovery' do
    rtu = lambda do |id = 'D-1'|
      result.call(measure: 'hvac_packaged_rooftop_heat_pump', configuration: 'RTU HP', group_key: [:delivery, id],
                  record_ids: [id, 'HS-1', 'CS-1'])
    end
    recovery = lambda do |links = ['D-1'], id: 'O-1', premises: building, type: 'Heat recovery ventilator'|
      result.call(measure: 'upgrade_hvac_exhaust_air_energy_or_heat_recovery', configuration: 'Recovery',
                  group_key: [:recovery, id], record_ids: [id] + links, premises:)
            .tap { |r| r.measure_arguments = { 'ventilation_type' => type } }
    end

    it 'appends one ComStock recovery step after sizing' do
      plan = plan_for([rtu.call, rtu.call('D-2'), recovery.call(['D-1']), recovery.call(['D-2'], id: 'O-2')], hvac_systems)

      expect(plan.status).to eq(:topology), plan.messages.join("\n")
      expect(plan.steps.map { |step| step[:measure_dir_name] }).to eq(
        ['apply_hvac_topology_to_zone_scope', 'apply_standard_hvac_sizing_and_efficiency',
         'upgrade_hvac_exhaust_air_energy_or_heat_recovery']
      )
      expect(plan.steps.last[:arguments]).to eq({})
    end

    it 'sets ComStock ERV effectiveness after recovery for an energy recovery ventilator' do
      plan = plan_for([rtu.call, recovery.call(type: 'Energy recovery ventilator')], hvac_systems)

      expect(plan.status).to eq(:topology), plan.messages.join("\n")
      expect(plan.steps.last(2)).to eq(
        [{ measure_dir_name: 'upgrade_hvac_exhaust_air_energy_or_heat_recovery', arguments: {} },
         { measure_dir_name: 'modify_existing_heat_recovery',
           arguments: { target_heat_exchanger_names: '*', effectiveness_metric: 'comstock_erv' } }]
      )
    end

    {
      'partial delivery coverage' => [-> { [rtu.call, rtu.call('D-2'), recovery.call] }, /does not serve deliveries D-2/],
      'zone equipment hosts' => [-> { [result.call(record_ids: ['D-1']), recovery.call] }, /not supported with PTAC/],
      'non-building scope' => [-> { [rtu.call, recovery.call(premises: [{ type: 'ThermalZone', id: 'TZ-1' }])] },
                               /must both serve the whole building/],
      'separate ventilation' => [-> { [rtu.call, recovery.call, result.call(measure: 'hvac_doas', group_key: [:other, 'O-9'])] },
                                 /cannot be combined with separate ventilation/],
      'mixed recovery types' => [lambda {
        [rtu.call, rtu.call('D-2'), recovery.call(['D-1']), recovery.call(['D-2'], id: 'O-2', type: 'Energy recovery ventilator')]
      }, /Mixed heat and energy recovery/]
    }.each do |label, (results, message)|
      it "falls back for #{label}" do
        plan = plan_for(instance_exec(&results), hvac_systems)

        expect(plan.status).to eq(:fallback)
        expect(plan.messages.join("\n")).to match(message)
      end
    end

    it 'plans the edited ASHRAE L2 fixture with recovery' do
      path = File.expand_path('../../files/v2.7.0/Example_ASHRAE_L2_Report_l200_erv.xml', __dir__)
      doc = REXML::Document.new(File.read(path), ignore_whitespace_nodes: :all)
      reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)
      plan = described_class.new.plan(reader.get_hvac_systems_xml, reader.get_standard_template)

      expect(reader.get_standard_template).to eq('90.1-2019')
      expect(plan.status).to eq(:topology), plan.messages.join("\n")
      expect(plan.steps.first[:arguments]).to include(topology_measure: 'hvac_packaged_rooftop_heat_pump',
                                                      topology_arguments_json: '{"supplemental_heating_fuel":"NaturalGas"}')
      expect(plan.steps.last[:measure_dir_name]).to eq('modify_existing_heat_recovery')
    end

    ['Example_ASHRAE_L2_Report.xml', 'BuildingEQ-1.0.0.xml'].each do |file_name|
      it "keeps #{file_name} on the fallback baseline" do
        path = File.expand_path("../../files/v2.7.0/#{file_name}", __dir__)
        doc = REXML::Document.new(File.read(path), ignore_whitespace_nodes: :all)
        reader = BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1)

        expect(described_class.new.plan(reader.get_hvac_systems_xml, reader.get_standard_template).status).to eq(:fallback)
      end
    end

    it 'folds the ASHRAE L2 economizer delivery and infers recovery integration' do
      path = File.expand_path('../../files/v2.7.0/Example_ASHRAE_L2_Report.xml', __dir__)
      doc = REXML::Document.new(File.read(path), ignore_whitespace_nodes: :all)
      results = BOSS::HvacTopologySelector.new.select(BOSS::BuildingSyncReader.new(doc, nil, ASHRAE90_1).get_hvac_systems_xml)

      expect(results.map { |r| r.record_ids.first }).not_to include('Delivery-45022140')
      recovery = results.find { |r| r.measure == 'upgrade_hvac_exhaust_air_energy_or_heat_recovery' }
      expect(recovery.status).to eq(:match), recovery.messages.join(' ')
      expect(recovery.record_ids.drop(1)).to eq(['Delivery-45022120'])
      expect(recovery.messages.join).to match(/Integration inferred/)
      expect(recovery.measure_arguments).to eq('ventilation_type' => 'Energy recovery ventilator')
    end
  end

  describe '.proposed_system_ids' do
    def systems_with_measures(measure_xml)
      xml = <<~XML
        <auc:BuildingSync xmlns:auc="http://buildingsync.net/schemas/bedes-auc/2019">
          <auc:Facilities><auc:Facility>
            <auc:Systems><auc:HVACSystems>
              <auc:HVACSystem ID="Existing"/><auc:HVACSystem ID="Alt"/><auc:HVACSystem ID="Mod"/>
            </auc:HVACSystems></auc:Systems>
            <auc:Measures>#{measure_xml}</auc:Measures>
          </auc:Facility></auc:Facilities>
        </auc:BuildingSync>
      XML
      REXML::XPath.first(REXML::Document.new(xml), "//*[local-name()='HVACSystems']")
    end

    it 'returns no IDs without HVACSystems or measure references' do
      expect(described_class.proposed_system_ids(nil)).to eq([])
      expect(described_class.proposed_system_ids(systems_with_measures(''))).to eq([])
    end

    it 'returns unique HVACSystem IDs named as alternatives or modified systems, without changing the XML' do
      systems = systems_with_measures(<<~XML)
        <auc:Measure ID="M1"><auc:TypeOfMeasure><auc:Replacements><auc:Replacement>
          <auc:ExistingSystemReplaced IDref="Existing"/>
          <auc:AlternativeSystemReplacement IDref="Alt"/>
          <auc:AlternativeSystemReplacement IDref="Alt"/>
          <auc:AlternativeSystemReplacement IDref="Lighting-1"/>
        </auc:Replacement></auc:Replacements></auc:TypeOfMeasure></auc:Measure>
        <auc:Measure ID="M2"><auc:TypeOfMeasure><auc:ModificationRetrocommissions><auc:ModificationRetrocommissioning>
          <auc:ModifiedSystem IDref="Mod"/>
        </auc:ModificationRetrocommissioning></auc:ModificationRetrocommissions></auc:TypeOfMeasure></auc:Measure>
      XML
      before = systems.document.to_s

      expect(described_class.proposed_system_ids(systems)).to eq(['Alt', 'Mod'])
      expect(systems.document.to_s).to eq(before)
    end
  end

  it 'plans the existing system when an unmappable proposed HVACSystem is excluded' do
    path = File.expand_path('../../files/v2.7.0/example-smalloffice-level2.xml', __dir__)
    doc = REXML::Document.new(File.read(path), ignore_whitespace_nodes: :all)
    hvac_systems = REXML::XPath.first(doc, "//*[local-name()='HVACSystems']")
    prefix = hvac_systems.prefix.empty? ? '' : "#{hvac_systems.prefix}:"
    hvac_systems.add_element("#{prefix}HVACSystem", 'ID' => 'Proposed-HVAC')
    measure = hvac_systems.parent.parent.add_element("#{prefix}Measures").add_element("#{prefix}Measure", 'ID' => 'M-1')
    ["#{prefix}TypeOfMeasure", "#{prefix}Replacements", "#{prefix}Replacement"]
      .reduce(measure) { |parent, name| parent.add_element(name) }
      .add_element("#{prefix}AlternativeSystemReplacement", 'IDref' => 'Proposed-HVAC')

    expect(described_class.new.plan(hvac_systems, 'DOE Ref 1980-2004').status).to eq(:fallback)
    plan = described_class.new.plan(hvac_systems, 'DOE Ref 1980-2004',
                                    exclude_system_ids: described_class.proposed_system_ids(hvac_systems))
    expect(plan.status).to eq(:topology), plan.messages.join("\n")
    expect(plan.steps.first[:arguments]).to include(topology_measure: 'hvac_packaged_rooftop_heat_pump', operation: 'create')
  end
end
