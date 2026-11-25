# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'json'
require 'tmpdir'
require 'rexml/document'
require 'BOSS/boss'
require 'BOSS/constants'

RSpec.describe 'Central furnace with cooling-only PTAC' do
  files_dir = File.expand_path('../../files/v2.7.0', __dir__)
  l200_path = File.join(files_dir, 'Example_NYC_Energy_Efficiency_Report_Property_2_l200.xml')
  original_path = File.join(files_dir, 'Example_NYC_Energy_Efficiency_Report_Property_2.xml')

  def hvac_systems(path)
    doc = REXML::Document.new(File.read(path), ignore_whitespace_nodes: :all)
    REXML::XPath.first(doc, "//*[local-name()='HVACSystems']")
  end

  def select(systems) = BOSS::HvacTopologySelector.new.select(systems)

  def element(systems, id) = REXML::XPath.first(systems, ".//*[@ID='#{id}']")

  it 'selects one result from standard elements' do
    results = select(hvac_systems(l200_path))
    expect(results.length).to eq 1
    result = results.first
    expect(result.status).to eq :match
    expect(result.measure).to eq 'hvac_heating_with_terminal_cooling'
    expect(result.measure_arguments).to eq('heating_source' => 'central_gas_furnace')
    expect(result.record_ids).to include('Delivery-44989380', 'Delivery-44989400', 'HeatingSource-44989520',
                                         'CoolingSource-44989500', 'OtherHVACSystemType-44989440')
    expect(result.messages.join(' ')).to include('CoolingSource-44989500 quantity 4')
  end

  it 'does not match the original XML, whose sources are shared and DX type is unstated' do
    expect(select(hvac_systems(original_path)).map(&:status)).not_to include(:match)
  end

  it 'does not match when the cooling source is not a PTAC' do
    systems = hvac_systems(l200_path)
    element(systems, 'CoolingSource-44989500').elements['.//*[local-name()="DXSystemType"]'].text = 'Split DX air conditioner'
    expect(select(systems).map(&:configuration)).not_to include('Central furnace with cooling-only PTAC')
  end

  it 'does not match when the heating delivery also references the cooling source' do
    systems = hvac_systems(l200_path)
    delivery = element(systems, 'Delivery-44989380')
    ref = REXML::Element.new('auc:CoolingSourceID')
    ref.add_attribute('IDref', 'CoolingSource-44989500')
    delivery.add_element(ref)
    expect(select(systems).map(&:status)).not_to include(:match)
  end

  it 'fails a guard on a local-fan heating delivery' do
    systems = hvac_systems(l200_path)
    element(systems, 'Delivery-44989380').elements['.//*[local-name()="AirDeliveryType"]'].text = 'Local fan'
    result = select(systems).first
    expect(result.status).to eq :conflicting_input
    expect(result.messages).to include('Guard failed: A/AirDeliveryType')
  end

  describe 'BOSS::Boss.write_baseline_osw' do
    it 'writes the topology steps and a mapping report' do
      Dir.mktmpdir do |dir|
        osw_path = BOSS::Boss.write_baseline_osw(l200_path, dir, nil, ASHRAE90_1, require_l200: true)
        osw = JSON.parse(File.read(osw_path))
        step = osw['steps'].find { |s| s['measure_dir_name'] == 'apply_hvac_topology_to_zone_scope' }
        expect(JSON.parse(step['arguments']['topology_arguments_json'])).to eq('heating_source' => 'central_gas_furnace')
        typical = osw['steps'].find { |s| s['measure_dir_name'] == 'create_typical_building_from_model' }
        expect(typical['arguments']['add_hvac']).to be false
        report = JSON.parse(File.read(File.join(dir, 'baseline', 'hvac_mapping_report.json')))
        expect(report['status']).to eq 'topology'
        expect(report['hvac_steps']).to eq ['apply_hvac_topology_to_zone_scope', 'apply_standard_hvac_sizing_and_efficiency']
      end
    end

    it 'raises in strict mode for the original XML' do
      Dir.mktmpdir do |dir|
        expect { BOSS::Boss.write_baseline_osw(original_path, dir, nil, ASHRAE90_1, require_l200: true) }
          .to raise_error(RuntimeError, /L200 HVAC topology required/)
        expect(Dir.children(dir)).to be_empty
      end
    end
  end
end
