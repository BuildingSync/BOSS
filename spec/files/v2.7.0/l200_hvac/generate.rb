# frozen_string_literal: true

# Generates L200 baseline HVAC examples that BaselineHvacPlanner resolves to a topology plan
# (no fallback). Each example is example-smalloffice-level2-built-2012.xml with its HVACSystem
# replaced by one supported configuration; the HVACSystem keeps the original LinkedPremises.
#
#   ruby spec/files/v2.7.0/l200_hvac/generate.rb

BASE = File.expand_path('../example-smalloffice-level2-built-2012.xml', __dir__)

def dx(type, condenser: nil, quantity: false)
  cn = condenser ? "<CondenserPlantIDs><CondenserPlantID IDref=\"#{condenser}\"/></CondenserPlantIDs>" : ''
  "<CoolingSourceType><DX><DXSystemType>#{type}</DXSystemType>#{cn}</DX></CoolingSourceType>" \
    "#{quantity ? '<Quantity>1</Quantity>' : ''}"
end

def heat_pump(type, backup)
  "<HeatingSourceType><HeatPump>#{type ? "<HeatPumpType>#{type}</HeatPumpType>" : ''}" \
    "#{backup ? "<HeatPumpBackupSystemFuel>#{backup}</HeatPumpBackupSystemFuel>" : ''}" \
    '<CoolingSourceID IDref="CoolingSource-1"/></HeatPump></HeatingSourceType>'
end

def central_air(terminal, reheat, extra = '')
  '<CentralAirDistribution><AirDeliveryType>Central fan</AirDeliveryType>' \
    "<TerminalUnit>#{terminal}</TerminalUnit><ReheatSource>#{reheat}</ReheatSource>#{extra}</CentralAirDistribution>"
end

def fan_coil(type)
  "<ZoneEquipment><FanBased><FanBasedDistributionType><FanCoil><FanCoilType>#{type}</FanCoilType>" \
    '</FanCoil></FanBasedDistributionType></FanBased></ZoneEquipment>'
end

ELECTRIC_RESISTANCE = '<HeatingSourceType><ElectricResistance/></HeatingSourceType>'
GAS_FURNACE = '<HeatingSourceType><Furnace><FurnaceType>Warm air</FurnaceType></Furnace></HeatingSourceType>' \
              '<PrimaryFuel>Natural gas</PrimaryFuel><HeatingMedium>Air</HeatingMedium>'
HOT_WATER = '<HeatingSourceType><SourceHeatingPlantID IDref="HeatingPlant-1"/></HeatingSourceType>' \
            '<HeatingMedium>Hot water</HeatingMedium>'
CHILLED_WATER = '<CoolingSourceType><CoolingPlantID IDref="CoolingPlant-1"/></CoolingSourceType>' \
                '<CoolingMedium>Chilled water</CoolingMedium><Quantity>1</Quantity>'
NO_HEATING = '<HeatingSourceType><NoHeating/></HeatingSourceType>'
NO_COOLING = '<CoolingSourceType><NoCooling/></CoolingSourceType>'
SINGLE_ZONE_CAV = central_air('CAV terminal box no reheat', 'None')
VAV_HW = central_air('VAV terminal box not fan powered with reheat', 'Heating plant', '<ReheatPlantID IDref="HeatingPlant-1"/>')

BOILER = '<HeatingPlants><HeatingPlant ID="HeatingPlant-1"><Boiler><BoilerType>Hot water</BoilerType></Boiler>' \
         '<PrimaryFuel>Natural gas</PrimaryFuel></HeatingPlant></HeatingPlants>'
CHILLER = '<CoolingPlants><CoolingPlant ID="CoolingPlant-1"><Chiller><ChillerType>Vapor compression</ChillerType>' \
          '<ChillerCompressorDriver>Electric Motor</ChillerCompressorDriver>' \
          '<CondenserPlantIDs><CondenserPlantID IDref="CondenserPlant-Tower"/></CondenserPlantIDs></Chiller></CoolingPlant></CoolingPlants>'
TOWER = '<CondenserPlant ID="CondenserPlant-Tower"><WaterCooled>' \
        '<WaterCooledCondenserType>Cooling tower</WaterCooledCondenserType></WaterCooled></CondenserPlant>'
AIR_CONDENSER = '<CondenserPlant ID="CondenserPlant-Air"><AirCooled/></CondenserPlant>'

# Conditioning configurations, one per DELIVERY_RULES :match row (heat pump backup fuel both ways).
CONDITIONING = {
  'ptac' => { delivery: '<ZoneEquipment/>', heating: ELECTRIC_RESISTANCE,
              cooling: dx('Packaged terminal air conditioner (PTAC)') },
  'pthp' => { delivery: '<ZoneEquipment/>', heating: heat_pump('Packaged Terminal', 'Electricity'),
              cooling: dx('Packaged terminal heat pump (PTHP)') },
  'rtu_ac' => { delivery: SINGLE_ZONE_CAV, heating: GAS_FURNACE, zoning: 'Single zone',
                cooling: dx('Packaged/unitary direct expansion/RTU') },
  'rtu_hp_electric_backup' => { delivery: SINGLE_ZONE_CAV, heating: heat_pump('Packaged Unitary', 'Electricity'),
                                zoning: 'Single zone', cooling: dx('Packaged/unitary heat pump') },
  'rtu_hp_gas_backup' => { delivery: SINGLE_ZONE_CAV, heating: heat_pump('Packaged Unitary', 'Natural gas'),
                           zoning: 'Single zone', cooling: dx('Packaged/unitary heat pump') },
  'warm_air_furnace' => { delivery: SINGLE_ZONE_CAV, heating: GAS_FURNACE, zoning: 'Single zone', cooling: NO_COOLING },
  'packaged_vav_hw_reheat' => { delivery: VAV_HW, heating: HOT_WATER, zoning: 'Multi zone',
                                cooling: dx('Packaged/unitary direct expansion/RTU', quantity: true), plants: BOILER },
  'vav_hw_reheat' => { delivery: VAV_HW, heating: HOT_WATER, zoning: 'Multi zone', cooling: CHILLED_WATER,
                       plants: BOILER + CHILLER, condensers: TOWER },
  'four_pipe_fan_coil' => { delivery: fan_coil('Fan coil 4 pipe'), heating: HOT_WATER, cooling: CHILLED_WATER,
                            plants: BOILER + CHILLER, condensers: TOWER },
  'vrf' => { delivery: fan_coil('VRF terminal units'), heating: heat_pump(nil, nil),
             cooling: dx('Variable refrigerant flow', condenser: 'CondenserPlant-Air', quantity: true),
             condensers: AIR_CONDENSER }
}.freeze

# example name => [conditioning, VentilationType or nil]. Ventilation pairs only with zone equipment.
EXAMPLES = CONDITIONING.keys.to_h { |name| [name, [name, nil]] }.merge(
  'ptac_ventilation_only' => ['ptac', 'Supply only'],
  'pthp_doas' => ['pthp', 'Dedicated outdoor air system'],
  'four_pipe_fan_coil_doas' => ['four_pipe_fan_coil', 'Dedicated outdoor air system'],
  'vrf_doas' => ['vrf', 'Dedicated outdoor air system']
).freeze

def hvac_system(spec, ventilation, premises)
  heating = "<HeatingSource ID=\"HeatingSource-1\">#{spec[:heating]}</HeatingSource>"
  cooling = "<CoolingSource ID=\"CoolingSource-1\">#{spec[:cooling]}</CoolingSource>"
  delivery = "<Delivery ID=\"Delivery-1\"><DeliveryType>#{spec[:delivery]}</DeliveryType>" \
             '<HeatingSourceID IDref="HeatingSource-1"/><CoolingSourceID IDref="CoolingSource-1"/></Delivery>'
  others = ''
  if ventilation
    heating += "<HeatingSource ID=\"HeatingSource-V\">#{NO_HEATING}</HeatingSource>"
    cooling += "<CoolingSource ID=\"CoolingSource-V\">#{NO_COOLING}</CoolingSource>"
    delivery += "<Delivery ID=\"Delivery-V\"><DeliveryType>#{SINGLE_ZONE_CAV}</DeliveryType>" \
                '<HeatingSourceID IDref="HeatingSource-V"/><CoolingSourceID IDref="CoolingSource-V"/></Delivery>'
    others = '<OtherHVACSystems><OtherHVACSystem ID="OtherHVACSystem-1"><OtherHVACType><MechanicalVentilation>' \
             "<VentilationType>#{ventilation}</VentilationType></MechanicalVentilation></OtherHVACType>" \
             '<Integration>Stand-alone</Integration>' \
             '<LinkedDeliveryIDs><LinkedDeliveryID IDref="Delivery-V"/></LinkedDeliveryIDs></OtherHVACSystem></OtherHVACSystems>'
  end
  zoning = spec[:zoning] ? "<ZoningSystemType>#{spec[:zoning]}</ZoningSystemType>" : ''
  condensers = spec[:condensers] ? "<CondenserPlants>#{spec[:condensers]}</CondenserPlants>" : ''
  plant_xml = "#{spec[:plants]}#{condensers}"
  plants = plant_xml.empty? ? '' : "<Plants>#{plant_xml}</Plants>"
  "<HVACSystem ID=\"HVACSystem-1\">#{plants}<HeatingAndCoolingSystems>#{zoning}" \
    "<HeatingSources>#{heating}</HeatingSources><CoolingSources>#{cooling}</CoolingSources>" \
    "<Deliveries>#{delivery}</Deliveries></HeatingAndCoolingSystems>#{others}#{premises}</HVACSystem>"
end

base = File.read(BASE)
block = base[%r{<HVACSystem ID="HVACSystem-1">.*?</HVACSystem>}m] or abort 'HVACSystem-1 not found'
premises = block[%r{<LinkedPremises>.*?</LinkedPremises>}m] or abort 'LinkedPremises not found'

EXAMPLES.each do |name, (conditioning, ventilation)|
  xml = base.sub(block, hvac_system(CONDITIONING.fetch(conditioning), ventilation, premises))
  File.write(File.join(__dir__, "l200_#{name}.xml"), xml)
  puts "l200_#{name}.xml"
end
