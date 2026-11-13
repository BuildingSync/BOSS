# HVAC Mapping Gaps Found In BOSS

Gaps between BuildingSync audit data and the `buildingsync-measures-gem` [HVAC Mapping and Migration Guide](https://github.com/BuildingSync/buildingsync-measures-gem/blob/develop/docs/HVAC_MAPPING_AND_MIGRATION.md), found while running `BOSS::HvacTopologySelector` on BOSS fixtures. To be moved to `buildingsync-measures-gem`. Rows the guide already lists as mapping gaps or not mappable (fan-powered VAV with electric reheat, water-loop and ground-source heat pumps, chilled beam, radiant, ERV/HRV, exhaust, natural ventilation) are not repeated here.

Fixture paths are under `spec/files/v2.7.0/`.

Status: gaps 1-7 were resolved upstream in buildingsync-measures-gem `e1b2f33` and adopted in `BOSS::HvacTopologySelector`. Gap 8 is open.

## Measure Gaps

### 1. Packaged unitary heat pump with gas backup

- Data: `example-smalloffice-level2.xml`, all five deliveries. `HeatPumpType = Packaged Unitary`, `HeatPumpBackupSystemFuel = Natural gas`, single-zone CAV delivery.
- Guide: the Packaged Rooftop Heat Pump row requires `HeatPumpBackupSystemFuel = Electricity`. No row covers gas backup, so the delivery identifies no configuration.
- Measure: `hvac_packaged_rooftop_heat_pump` creates electric supplemental heat only.
- Ask: add a gas-supplemental option to the measure and a guide row, or list gas-backup packaged heat pumps as not mappable.

### 2. Packaged rooftop AC with `FurnaceType = Other`

- Data: `Reference-PrimarySchool-L200-Audit.xml`, PSZAC deliveries. Gas furnace (`PrimaryFuel = Natural gas`, `HeatingMedium = Air`) with `FurnaceType = Other`, packaged RTU DX, single-zone CAV.
- Guide: the Packaged Rooftop Air Conditioner and Warm Air Furnace rows require `FurnaceType = Warm air`.
- Ask: decide whether `Other` (or absent) `FurnaceType` with gas fuel and air medium may match, or list it explicitly as missing input.

## Guide Rule Gaps

### 3. Empty `FanBased/FanBasedDistributionType`

- Data: `Reference-PrimarySchool-L200-Audit.xml`, every delivery. `FanBased` holds an empty `<FanBasedDistributionType/>` next to `AirSideEconomizer` data. The element is optional in the schema.
- Guide: packaged rooftop, VAV, and PTAC/PTHP rows require `absent(A/FanBased/FanBasedDistributionType)` (or `Z/...`). An empty element fails that check, so economizer data blocks the match.
- Ask: treat an empty `FanBasedDistributionType` as absent, or require "no child elements" instead of "absent".

### 4. `CS/Quantity = 1` as a required predicate

- Data: `Reference-PrimarySchool-L200-Audit.xml`, VAV pods. The DX cooling sources omit `Quantity`.
- Guide: Packaged Rooftop VAV with Hot Water Reheat (and VAV with Hot Water Reheat, VRF) list `CS/Quantity = 1` under required cooling predicates, while other `Quantity` checks are guards that pass when absent.
- Ask: make `CS/Quantity` a guard (pass when absent), or confirm it must be supplied.

### 5. Integrated outdoor-air records

- Data: `Reference-PrimarySchool-L200-Audit.xml`. Per-zone `OtherHVACSystem` records with `VentilationType = Supply only` and `Integration = Integrated with central air distribution`, several linked to one VAV delivery, plus integrated records on PSZAC deliveries.
- Guide: only Stand-alone ventilation is defined. The guide does not say whether integrated records consume the linked delivery, so multiple records on one delivery read as a conflict, and an integrated record on a conditioned delivery reads as a conditioned DOAS.
- BOSS behavior: records with `Integration` `Integrated with central air distribution` or `Integrated with local air distribution` do not consume deliveries; they return `integrated`, and the linked deliveries are selected as conditioning deliveries.
- Ask: add this rule to the guide. `DemandControlVentilation` and `VentilationRate` on these records may later feed a modifier mapping.

### 6. `VentilationType None` or untyped ventilation on conditioned deliveries

- Data: ASHRAE L1/L2 exports (`Chula_Vista_ASHRAE_L*`, `Demo_ASHRAE_L2_Example_Building.xml`, `Example_ASHRAE_L2_Report_-_with_Energy_Use_Data*.xml`, `Example_HOMES_Template_Building.xml`, NYC files). `OtherHVACSystem` with only `MechanicalVentilation` (`VentilationType None` or none, optional `DemandControlVentilation`) links conditioned deliveries.
- Guide: the Explicitly no HVAC row covers only unconditioned deliveries; other cases are undefined.
- BOSS behavior: such records consume deliveries only when all linked deliveries are explicitly unconditioned. Otherwise the deliveries are selected as conditioning deliveries, and the record returns `no_hvac` (`None`) or `missing_input` (no type).
- Ask: add this rule to the guide.

### 7. Premises linked only on `HVACSystem`

- Data: every v2.7.0 fixture with detailed records links `LinkedPremises` on `HVACSystem`, not on `Delivery` or `OtherHVACSystem`.
- Guide: `zones(D)` and `zones(O)` come from the record's own links.
- BOSS behavior: a record without its own links inherits the parent `HVACSystem` links.
- Ask: add the fallback to the guide.

## Open

### 8. DX cooling source without a condenser plant

- Data: `example-smalloffice-level2.xml`, all five DX sources (`DXSystemType = Packaged/unitary heat pump`) omit `CondenserPlantIDs`.
- Guide: packaged and PTAC/PTHP/VRF rows require the DX condenser to resolve to an `AirCooled` condenser plant, so these deliveries identify no configuration.
- Ask: decide whether a packaged or terminal DX source without a condenser reference may be treated as air-cooled, or confirm it stays missing input.
