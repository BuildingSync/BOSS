# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'rexml/document'
require 'BOSS/hvac_topology_selector'

RSpec.describe BOSS::HvacTopologySelector do
  dx = lambda do |type, condenser = 'CN-AIR'|
    "<CoolingSourceType><DX><DXSystemType>#{type}</DXSystemType>" \
      "<CondenserPlantIDs><CondenserPlantID IDref=\"#{condenser}\"/></CondenserPlantIDs></DX></CoolingSourceType>"
  end
  heat_pump = lambda do |type, backup = 'Electricity'|
    backup_xml = backup ? "<HeatPumpBackupSystemFuel>#{backup}</HeatPumpBackupSystemFuel>" : ''
    "<HeatingSourceType><HeatPump>#{type ? "<HeatPumpType>#{type}</HeatPumpType>" : ''}" \
      "<CoolingSourceID IDref=\"CS-1\"/>#{backup_xml}</HeatPump></HeatingSourceType>"
  end
  central_air = lambda do |terminal, reheat, extra = ''|
    "<CentralAirDistribution><AirDeliveryType>Central fan</AirDeliveryType><TerminalUnit>#{terminal}</TerminalUnit>" \
      "<ReheatSource>#{reheat}</ReheatSource>#{extra}</CentralAirDistribution>"
  end

  electric_resistance = '<HeatingSourceType><ElectricResistance/></HeatingSourceType>'
  gas_furnace = '<PrimaryFuel>Natural gas</PrimaryFuel><HeatingMedium>Air</HeatingMedium><HeatingSourceType><Furnace><FurnaceType>Warm air</FurnaceType></Furnace></HeatingSourceType>'
  hot_water = '<HeatingMedium>Hot water</HeatingMedium><HeatingSourceType><SourceHeatingPlantID IDref="HP-1"/></HeatingSourceType>'
  chilled_water = '<CoolingMedium>Chilled water</CoolingMedium><CoolingSourceType><CoolingPlantID IDref="CP-1"/></CoolingSourceType>'
  no_cooling = '<CoolingSourceType><NoCooling/></CoolingSourceType>'
  no_heating = '<HeatingSourceType><NoHeating/></HeatingSourceType>'
  single_zone_cav = central_air.call('CAV terminal box no reheat', 'None')
  vav_hw = central_air.call('VAV terminal box not fan powered with reheat', 'Heating plant', '<ReheatPlantID IDref="HP-1"/>')
  fan_coil = ->(type) { "<ZoneEquipment><FanBased><FanBasedDistributionType><FanCoil><FanCoilType>#{type}</FanCoilType></FanCoil></FanBasedDistributionType></FanBased></ZoneEquipment>" }

  air_condenser = '<CondenserPlants><CondenserPlant ID="CN-AIR"><AirCooled/></CondenserPlant></CondenserPlants>'
  hydronic_plants = '<HeatingPlants><HeatingPlant ID="HP-1"><Boiler><BoilerType>Hot water</BoilerType></Boiler>' \
                    '<PrimaryFuel>Natural gas</PrimaryFuel></HeatingPlant></HeatingPlants>' \
                    '<CoolingPlants><CoolingPlant ID="CP-1"><Chiller><ChillerType>Vapor compression</ChillerType>' \
                    '<ChillerCompressorDriver>Electric Motor</ChillerCompressorDriver>' \
                    '<CondenserPlantIDs><CondenserPlantID IDref="CN-TOWER"/></CondenserPlantIDs></Chiller></CoolingPlant></CoolingPlants>' \
                    '<CondenserPlants><CondenserPlant ID="CN-TOWER"><WaterCooled>' \
                    '<WaterCooledCondenserType>Cooling tower</WaterCooledCondenserType></WaterCooled></CondenserPlant></CondenserPlants>'
  all_plants = hydronic_plants + air_condenser
  premises = '<LinkedPremises><ThermalZone><LinkedThermalZoneID IDref="TZ-1"/></ThermalZone></LinkedPremises>'

  # One HVACSystem with a single HS/CS/Delivery triple plus optional plants and other systems.
  system_xml = lambda do |delivery:, heating:, cooling:, zoning: nil, plants: all_plants, others: '', delivery_refs: nil,
                          delivery_premises: premises, cooling_extra: ''|
    refs = delivery_refs || '<HeatingSourceID IDref="HS-1"/><CoolingSourceID IDref="CS-1"/>'
    zoning_xml = zoning ? "<ZoningSystemType>#{zoning}</ZoningSystemType>" : ''
    '<HeatingAndCoolingSystems>' \
      "#{zoning_xml}<HeatingSources><HeatingSource ID=\"HS-1\">#{heating}</HeatingSource></HeatingSources>" \
      "<CoolingSources><CoolingSource ID=\"CS-1\">#{cooling}#{cooling_extra}</CoolingSource></CoolingSources>" \
      "<Deliveries><Delivery ID=\"D-1\">#{delivery_premises}<DeliveryType>#{delivery}</DeliveryType>#{refs}</Delivery></Deliveries>" \
      "</HeatingAndCoolingSystems><Plants>#{plants}</Plants>#{others}"
  end

  def select_from(body, prefix: nil)
    ns = prefix ? "xmlns:#{prefix}=\"http://buildingsync.net/schemas/bedes-auc/2019\"" : ''
    xml = "<BuildingSync #{ns}><HVACSystems><HVACSystem ID=\"HVAC-1\">#{body}</HVACSystem></HVACSystems></BuildingSync>"
    xml = xml.gsub(%r{<(/?)([A-Za-z])}, "<\\1#{prefix}:\\2") if prefix
    doc = REXML::Document.new(xml)
    described_class.new.select(doc.root.elements.to_a.first)
  end

  exact_cases = {
    'Packaged Terminal Air Conditioner' => ['hvac_ptac', { delivery: '<ZoneEquipment/>', heating: electric_resistance,
                                                           cooling: dx.call('Packaged terminal air conditioner (PTAC)') }],
    'Packaged Terminal Heat Pump' => ['hvac_pthp', { delivery: '<ZoneEquipment/>', heating: heat_pump.call('Packaged Terminal'),
                                                     cooling: dx.call('Packaged terminal heat pump (PTHP)') }],
    'Packaged Rooftop Air Conditioner' => ['hvac_packaged_rooftop_ac', { delivery: single_zone_cav, heating: gas_furnace,
                                                                         cooling: dx.call('Packaged/unitary direct expansion/RTU'),
                                                                         zoning: 'Single zone' }],
    'Packaged Rooftop Heat Pump' => ['hvac_packaged_rooftop_heat_pump', { delivery: single_zone_cav,
                                                                          heating: heat_pump.call('Packaged Unitary'),
                                                                          cooling: dx.call('Packaged/unitary heat pump'),
                                                                          zoning: 'Single zone' }],
    'Warm Air Furnace' => ['hvac_warm_air_furnace', { delivery: single_zone_cav, heating: gas_furnace, cooling: no_cooling,
                                                      zoning: 'Single zone' }],
    'Four Pipe Fan Coil Unit' => ['hvac_four_pipe_fan_coil', { delivery: fan_coil.call('Fan coil 4 pipe'), heating: hot_water,
                                                               cooling: chilled_water }],
    'VAV with Hot Water Reheat' => ['hvac_vav_hw_reheat', { delivery: vav_hw, heating: hot_water, cooling: chilled_water,
                                                            zoning: 'Multi zone', cooling_extra: '<Quantity>1</Quantity>' }],
    'Packaged Rooftop VAV with Hot Water Reheat' => ['hvac_packaged_rooftop_vav_hw_reheat', {
      delivery: vav_hw, heating: hot_water, cooling: dx.call('Packaged/unitary direct expansion/RTU'), zoning: 'Multi zone',
      cooling_extra: '<Quantity>1</Quantity>'
    }],
    'VRF Terminal Unit' => ['hvac_vrf', { delivery: fan_coil.call('VRF terminal units'), heating: heat_pump.call(nil, nil),
                                          cooling: dx.call('Variable refrigerant flow'), cooling_extra: '<Quantity>1</Quantity>' }]
  }

  describe 'exact matches' do
    exact_cases.each do |configuration, (measure, args)|
      it "selects #{measure} for #{configuration}" do
        results = select_from(system_xml.call(**args))
        expect(results.length).to eq(1)
        result = results.first
        expect(result.messages).to eq([])
        expect(result).to have_attributes(status: :match, configuration: configuration, measure: measure,
                                          hvac_system_id: 'HVAC-1', premises: [{ type: 'ThermalZone', id: 'TZ-1' }])
      end
    end

    it 'groups VAV by cooling source and fan coils by plant tuple' do
      vav = select_from(system_xml.call(**exact_cases['VAV with Hot Water Reheat'][1])).first
      fcu = select_from(system_xml.call(**exact_cases['Four Pipe Fan Coil Unit'][1])).first
      expect(vav.group_key).to eq([:cooling_source, 'CS-1'])
      expect(fcu.group_key).to eq([:plants, 'HP-1', 'CP-1', 'CN-TOWER'])
    end

    it 'treats an empty FanBasedDistributionType as absent' do
      args = exact_cases['Packaged Terminal Air Conditioner'][1]
      delivery = '<ZoneEquipment><FanBased><FanBasedDistributionType/></FanBased></ZoneEquipment>'
      expect(select_from(system_xml.call(**args, delivery:)).first.status).to eq(:match)
    end

    it 'accepts FurnaceType Other or absent and rejects other furnace types' do
      args = exact_cases['Warm Air Furnace'][1]
      other = select_from(system_xml.call(**args, heating: gas_furnace.sub('Warm air', 'Other'))).first
      absent = select_from(system_xml.call(**args, heating: gas_furnace.sub('<FurnaceType>Warm air</FurnaceType>', ''))).first
      steam = select_from(system_xml.call(**args, heating: gas_furnace.sub('Warm air', 'Steam'))).first
      expect([other.status, absent.status, steam.status]).to eq([:match, :match, :conflicting_input])
    end

    it 'passes the heat pump backup fuel as a measure argument' do
      args = exact_cases['Packaged Rooftop Heat Pump'][1]
      electric = select_from(system_xml.call(**args)).first
      gas = select_from(system_xml.call(**args, heating: heat_pump.call('Packaged Unitary', 'Natural gas'))).first
      expect(electric.measure_arguments).to eq('supplemental_heating_fuel' => 'Electricity')
      expect(gas).to have_attributes(status: :match, measure_arguments: { 'supplemental_heating_fuel' => 'NaturalGas' })
    end

    it 'treats CS/Quantity as a guard on VAV and VRF rows' do
      ['VAV with Hot Water Reheat', 'VRF Terminal Unit'].each do |configuration|
        args = exact_cases[configuration][1]
        expect(select_from(system_xml.call(**args, cooling_extra: '')).first.status).to eq(:match)
        expect(select_from(system_xml.call(**args, cooling_extra: '<Quantity>2</Quantity>')).first.status).to eq(:conflicting_input)
      end
    end

    it 'reads an omitted condenser reference as air-cooled for packaged DX but not VRF' do
      strip = ->(xml) { xml.sub(%r{<CondenserPlantIDs>.*?</CondenserPlantIDs>}, '') }
      ['Packaged Terminal Air Conditioner', 'Packaged Rooftop Heat Pump', 'Packaged Rooftop VAV with Hot Water Reheat'].each do |configuration|
        args = exact_cases[configuration][1]
        expect(select_from(system_xml.call(**args, cooling: strip.call(args[:cooling]))).first.status).to eq(:match)
      end
      vrf = exact_cases['VRF Terminal Unit'][1]
      expect(select_from(system_xml.call(**vrf, cooling: strip.call(vrf[:cooling]))).first.status).not_to eq(:match)
    end

    it 'ignores namespace prefixes' do
      result = select_from(system_xml.call(**exact_cases['Packaged Terminal Air Conditioner'][1]), prefix: 'auc').first
      expect(result).to have_attributes(status: :match, measure: 'hvac_ptac')
    end
  end

  describe 'non-match results' do
    {
      'mapping gap for fan-powered VAV with electric reheat' => [
        :mapping_gap, 'hvac_packaged_rooftop_vav_electric_reheat',
        { delivery: central_air.call('VAV terminal box fan powered with reheat', 'Local electric resistance'),
          heating: electric_resistance, cooling: dx.call('Packaged/unitary direct expansion/RTU'), zoning: 'Multi zone' }
      ],
      'mapping gap for ground source heat pump' => [
        :mapping_gap, 'hvac_ground_source_heat_pump',
        { delivery: '<ZoneEquipment/>', heating: heat_pump.call(nil, nil), cooling: dx.call('Other', 'CN-G'),
          plants: '<CondenserPlants><CondenserPlant ID="CN-G"><GroundSource/></CondenserPlant></CondenserPlants>' }
      ],
      'not mappable for split DX' => [
        :not_mappable, nil,
        { delivery: single_zone_cav, heating: gas_furnace, cooling: dx.call('Split DX air conditioner'), zoning: 'Single zone' }
      ],
      'not mappable for two-pipe fan coil' => [
        :not_mappable, nil, { delivery: fan_coil.call('Fan coil 2 pipe'), heating: hot_water, cooling: chilled_water }
      ],
      'not mappable for air-cooled chiller' => [
        :not_mappable, nil,
        { delivery: fan_coil.call('Fan coil 4 pipe'), heating: hot_water, cooling: chilled_water,
          plants: all_plants.sub('<WaterCooled><WaterCooledCondenserType>Cooling tower</WaterCooledCondenserType></WaterCooled>',
                                 '<AirCooled/>') }
      ],
      'missing input when the cooling source reference is absent' => [
        :missing_input, nil,
        { delivery: '<ZoneEquipment/>', heating: electric_resistance, cooling: dx.call('Packaged terminal air conditioner (PTAC)'),
          delivery_refs: '<HeatingSourceID IDref="HS-1"/>' }
      ],
      'missing input when the delivery has no linked premises' => [
        :missing_input, nil,
        { delivery: '<ZoneEquipment/>', heating: electric_resistance, cooling: dx.call('Packaged terminal air conditioner (PTAC)'),
          delivery_premises: '' }
      ],
      'missing input when detailed data identifies no configuration' => [
        :missing_input, nil, { delivery: '<ZoneEquipment/>', heating: electric_resistance, cooling: no_cooling }
      ],
      'conflicting input for a broken condenser reference' => [
        :conflicting_input, nil,
        { delivery: '<ZoneEquipment/>', heating: electric_resistance,
          cooling: dx.call('Packaged terminal air conditioner (PTAC)', 'CN-MISSING') }
      ],
      'conflicting input for a failed fuel guard' => [
        :conflicting_input, nil,
        { delivery: '<ZoneEquipment/>', heating: "<PrimaryFuel>Natural gas</PrimaryFuel>#{electric_resistance}",
          cooling: dx.call('Packaged terminal air conditioner (PTAC)') }
      ],
      'conflicting input for a required-absent element' => [
        :conflicting_input, nil,
        { delivery: fan_coil.call('Fan coil 4 pipe'),
          heating: electric_resistance, cooling: dx.call('Packaged terminal air conditioner (PTAC)') }
      ],
      'conflicting input for four-pipe fan coil with 2 pipe configuration' => [
        :conflicting_input, nil,
        { delivery: fan_coil.call('Fan coil 4 pipe').sub('</FanCoilType>', '</FanCoilType><HVACPipeConfiguration>2 pipe</HVACPipeConfiguration>'),
          heating: hot_water, cooling: chilled_water }
      ]
    }.each do |description, (status, measure, args)|
      it "reports #{description}" do
        results = select_from(system_xml.call(**args))
        expect(results.length).to eq(1)
        expect(results.first.status).to eq(status)
        expect(results.first.measure).to eq(measure)
        expect(results.first.messages).not_to be_empty
      end
    end

    it 'reports family-only data as missing input' do
      result = select_from('<PrincipalHVACSystemType>Packaged Rooftop Air Conditioner</PrincipalHVACSystemType>').first
      expect(result.status).to eq(:missing_input)
      expect(result.messages.first).to include('family-level data')
    end

    it 'reports duplicate IDs as conflicting input' do
      body = system_xml.call(**exact_cases['Packaged Terminal Air Conditioner'][1]).sub('CN-AIR"><AirCooled/>', 'HS-1"><AirCooled/>')
      expect(select_from(body).first.status).to eq(:conflicting_input)
    end

    it 'inherits HVACSystem linked premises when the delivery has none' do
      system_premises = '<LinkedPremises><Building><LinkedBuildingID IDref="B-1"/></Building></LinkedPremises>'
      body = system_xml.call(**exact_cases['Packaged Terminal Air Conditioner'][1], delivery_premises: '') + system_premises
      expect(select_from(body).first).to have_attributes(status: :match, premises: [{ type: 'Building', id: 'B-1' }])
    end

    it 'keeps delivery linked premises over HVACSystem linked premises' do
      system_premises = '<LinkedPremises><Building><LinkedBuildingID IDref="B-1"/></Building></LinkedPremises>'
      body = system_xml.call(**exact_cases['Packaged Terminal Air Conditioner'][1]) + system_premises
      expect(select_from(body).first.premises).to eq([{ type: 'ThermalZone', id: 'TZ-1' }])
    end
  end

  describe 'ventilation and other HVAC systems' do
    ventilation_delivery = "<Delivery ID=\"D-V\">#{premises}<DeliveryType>#{single_zone_cav}</DeliveryType>" \
                           '<HeatingSourceID IDref="HS-V"/><CoolingSourceID IDref="CS-V"/></Delivery>'
    other = lambda do |type_xml, links: '<LinkedDeliveryIDs><LinkedDeliveryID IDref="D-V"/></LinkedDeliveryIDs>',
                       integration: 'Stand-alone'|
      "<OtherHVACSystems><OtherHVACSystem ID=\"O-1\"><OtherHVACType>#{type_xml}</OtherHVACType>" \
        "<Integration>#{integration}</Integration>#{links}</OtherHVACSystem></OtherHVACSystems>"
    end
    mechanical = ->(type) { "<MechanicalVentilation><VentilationType>#{type}</VentilationType></MechanicalVentilation>" }

    with_ventilation = lambda do |others, ventilation_heating: no_heating|
      system_xml.call(**exact_cases['Packaged Terminal Air Conditioner'][1], others: others)
                .sub('</HeatingSources>', "<HeatingSource ID=\"HS-V\">#{ventilation_heating}</HeatingSource></HeatingSources>")
                .sub('</CoolingSources>', "<CoolingSource ID=\"CS-V\">#{no_cooling}</CoolingSource></CoolingSources>")
                .sub('</Deliveries>', "#{ventilation_delivery}</Deliveries>")
    end

    it 'selects PTAC plus DOAS as separate results' do
      results = select_from(with_ventilation.call(other.call(mechanical.call('Dedicated outdoor air system'))))
      expect(results.map { |r| [r.status, r.measure] }).to eq([[:match, 'hvac_ptac'], [:match, 'hvac_doas']])
      expect(results.last.group_key).to eq([:other, 'O-1'])
      expect(results.last.record_ids).to eq(['O-1', 'D-V'])
    end

    it 'selects ventilation only for supply-only ventilation' do
      results = select_from(with_ventilation.call(other.call(mechanical.call('Supply only'))))
      expect(results.last).to have_attributes(status: :match, measure: 'hvac_ventilation_only')
    end

    it 'reports conditioned DOAS as not mappable' do
      results = select_from(with_ventilation.call(other.call(mechanical.call('Dedicated outdoor air system')),
                                                  ventilation_heating: electric_resistance))
      expect(results.last.status).to eq(:not_mappable)
    end

    it 'reports energy recovery ventilation as not mappable without dropping it' do
      results = select_from(with_ventilation.call(other.call(mechanical.call('Energy recovery ventilator'))))
      expect(results.map(&:status)).to eq([:match, :not_mappable])
    end

    it 'reports humidifiers as not mappable' do
      results = select_from(with_ventilation.call(other.call('<Humidifier/>', links: '')))
      expect(results.last).to have_attributes(status: :not_mappable,
                                              configuration: 'Humidification / dehumidification / air cleaning')
    end

    it 'reports a broken linked delivery as conflicting input' do
      links = '<LinkedDeliveryIDs><LinkedDeliveryID IDref="D-MISSING"/></LinkedDeliveryIDs>'
      results = select_from(with_ventilation.call(other.call(mechanical.call('Supply only'), links: links)))
      expect(results.last.status).to eq(:conflicting_input)
    end

    conditioning_link = '<LinkedDeliveryIDs><LinkedDeliveryID IDref="D-1"/></LinkedDeliveryIDs>'

    it 'still selects conditioning deliveries linked by VentilationType None' do
      results = select_from(with_ventilation.call(other.call(mechanical.call('None'), links: conditioning_link)))
      expect(results.map(&:status)).to eq([:match, :missing_input, :no_hvac])
      expect(results.first.measure).to eq('hvac_ptac')
      expect(results.last.configuration).to eq('No separate ventilation equipment')
    end

    it 'still selects conditioning deliveries linked by an untyped ventilation record' do
      untyped = '<MechanicalVentilation><DemandControlVentilation>false</DemandControlVentilation></MechanicalVentilation>'
      results = select_from(with_ventilation.call(other.call(untyped, links: conditioning_link)))
      expect(results.first).to have_attributes(status: :match, measure: 'hvac_ptac')
      expect(results.last.status).to eq(:missing_input)
    end

    it 'still selects conditioning deliveries linked by integrated outdoor air records' do
      integrated = other.call(mechanical.call('Supply only'), links: conditioning_link,
                                                              integration: 'Integrated with central air distribution')
      second = integrated[%r{<OtherHVACSystem .*</OtherHVACSystem>}].sub('O-1', 'O-2')
      results = select_from(with_ventilation.call(integrated.sub('</OtherHVACSystems>', "#{second}</OtherHVACSystems>")))
      expect(results.map(&:status)).to eq([:match, :missing_input, :integrated, :integrated])
      expect(results.first.measure).to eq('hvac_ptac')
    end

    it 'lets VentilationType None own explicitly unconditioned deliveries' do
      body = with_ventilation.call(other.call(mechanical.call('None'))).sub("<DeliveryType>#{single_zone_cav}</DeliveryType>", '')
      results = select_from(body)
      expect(results.map(&:status)).to eq([:match, :no_hvac])
      expect(results.last.configuration).to eq('Explicitly no HVAC')
    end
  end
end
