# L200 baseline HVAC examples

BuildingSync files whose detailed HVAC data maps to a buildingsync-measures-gem topology, so
`BaselineHvacPlanner` builds the L200 baseline HVAC workflow instead of falling back to the L100
generic HVAC workflow (`create_typical_building_from_model` with `add_hvac = true`).

Each file is `../example-smalloffice-level2-built-2012.xml` (template 90.1-2013) with its
`HVACSystem` replaced by one supported configuration. The new `HVACSystem` keeps the original
`LinkedPremises`, which cover the whole building.

## Regenerating

The XML files are generated; edit `generate.rb` rather than the XML, then run from the repo root:

```
ruby spec/files/v2.7.0/l200_hvac/generate.rb
```

- `CONDITIONING` defines one conditioning configuration per supported selector rule
  (`DELIVERY_RULES` rows with status `:match` in `lib/BOSS/hvac_topology_selector.rb`).
- `EXAMPLES` maps each output name to a conditioning configuration plus an optional
  `VentilationType` (`Supply only` or `Dedicated outdoor air system`). Ventilation adds a
  stand-alone `OtherHVACSystem` linked to an unconditioned single-duct CAV delivery.
- The planner only accepts ventilation alongside zone equipment (PTAC, PTHP, four-pipe fan coil,
  VRF), so do not pair it with rooftop, furnace, or VAV configurations.

After adding an example, add it to `topology_configs` in
`spec/tests/integration/write_and_run_osws_spec.rb`.

## Coverage

Every plan ends with `apply_standard_hvac_sizing_and_efficiency`.

| Example | Planned topology measures |
|---|---|
| `l200_ptac.xml` | `hvac_ptac` |
| `l200_pthp.xml` | `hvac_pthp` |
| `l200_rtu_ac.xml` | `hvac_packaged_rooftop_ac` |
| `l200_rtu_hp_electric_backup.xml` | `hvac_packaged_rooftop_heat_pump` (electric supplemental heat) |
| `l200_rtu_hp_gas_backup.xml` | `hvac_packaged_rooftop_heat_pump` (natural gas supplemental heat) |
| `l200_warm_air_furnace.xml` | `hvac_warm_air_furnace` |
| `l200_packaged_vav_hw_reheat.xml` | `hvac_packaged_rooftop_vav_hw_reheat` |
| `l200_vav_hw_reheat.xml` | `hvac_vav_hw_reheat` |
| `l200_four_pipe_fan_coil.xml` | `hvac_four_pipe_fan_coil` |
| `l200_vrf.xml` | `hvac_vrf` |
| `l200_ptac_ventilation_only.xml` | `hvac_ptac` + `hvac_ventilation_only` |
| `l200_pthp_doas.xml` | `hvac_pthp` + `hvac_doas` |
| `l200_four_pipe_fan_coil_doas.xml` | `hvac_four_pipe_fan_coil` + `hvac_doas` |
| `l200_vrf_doas.xml` | `hvac_vrf` + `hvac_doas` |

Not covered: mapping-gap configurations (packaged/built-up VAV with electric reheat, water-loop
heat pump, ground-source heat pump, chilled beam, radiant) always fall back to L100 until their
gaps are resolved.
