# BOSS

BuildingSync OpenStudio Simulator (BOSS) takes in BuildingSync files, creates OpenStudio workflows from their contents, and runs those workflows to create models.


1. Install OpenStudio 3.10. Check installation with 
    ```console
    openstudio --version
    3.10.0+ce46db07de
    ```

2. Set enviroment variable `RUBYLIB` to the location of your openstudio installation. Check env var with:
    ```console
    echo $RUBYLIB
    /Applications/OpenStudio-3.10.0/Ruby
    ```

3. From local repo, bundle install

    ```bash
    bundle install
    ```

4. Install external non-gem measure repositories declared in the shipped manifest.

    ```bash
    bundle exec rake measures:install_external
    ```

5. (Optional) List resolved external measure roots.

    ```bash
    bundle exec rake measures:list_external
    ```

The shipped manifest lives at [config/external_measure_repos.yml](config/external_measure_repos.yml) and is preconfigured with:

- local measure roots: `lib/measures` (first in precedence)
- external repository: comstock (`measures` and `resources/measures`), pinned to commit `393de7bf`; later revisions of its recovery measure require the `comstock-typical` gem, which BOSS does not bundle
- local checkout: `buildingsync-measures-gem` (`lib/measures`), expected as a sibling of this repository (`../buildingsync-measures-gem`). It is marked `scenario_only` and is added to `measure_paths` only for baselines that use an HVAC topology. CI pins its commit via `BSYNC_MEASURES_REF` in [.github/workflows/ci.yml](.github/workflows/ci.yml).

Measure path precedence is:

1. local measure roots from [config/external_measure_repos.yml](config/external_measure_repos.yml)
2. gem-provided measure directories
3. external non-gem repository measure roots from [config/external_measure_repos.yml](config/external_measure_repos.yml)

The generated `in.osw` will include these paths in order under `measure_paths`.

### Baseline HVAC

When the facility's detailed (L200) `HVACSystems` exactly match a supported topology, the baseline sets `create_typical_building_from_model`'s `add_hvac` to `false` and adds `apply_hvac_topology_to_zone_scope` (operation `create`) and `apply_standard_hvac_sizing_and_efficiency` from buildingsync-measures-gem. Supported templates are DOE Ref Pre-1980, DOE Ref 1980-2004, and 90.1-2004 through 90.1-2019. HVAC systems referenced by measures as proposed (`AlternativeSystemReplacement` or `ModifiedSystem`) are excluded from the baseline.

Configurations that can produce a topology baseline:

| Configuration | Topology measure |
|---|---|
| Packaged Terminal Air Conditioner | `hvac_ptac` |
| Packaged Terminal Heat Pump | `hvac_pthp` |
| Four Pipe Fan Coil Unit | `hvac_four_pipe_fan_coil` |
| Packaged Rooftop Air Conditioner | `hvac_packaged_rooftop_ac` |
| Packaged Rooftop Heat Pump | `hvac_packaged_rooftop_heat_pump` |
| Packaged Rooftop VAV with Hot Water Reheat | `hvac_packaged_rooftop_vav_hw_reheat` |
| VAV with Hot Water Reheat | `hvac_vav_hw_reheat` |
| Warm Air Furnace | `hvac_warm_air_furnace` |
| VRF Terminal Unit | `hvac_vrf` |

A Ventilation Only (`hvac_ventilation_only`) or Dedicated Outdoor Air System (`hvac_doas`) configuration can be added on top, but only alongside PTAC, PTHP, four-pipe fan coil, or VRF.

A heat recovery or energy recovery ventilator (`OtherHVACSystem` with `Integration` `Integrated with central air distribution`) is applied after sizing with ComStock's `upgrade_hvac_exhaust_air_energy_or_heat_recovery`. When `Integration` is empty it is inferred as central-air integration if every linked delivery is central air distribution. A zone-equipment delivery that holds only fan-based economizer/reset controls and shares its heating and cooling sources with exactly one central-fan delivery is treated as that delivery's controls. Recovery is supported only with packaged rooftop AC/heat pump, warm air furnace, and the two VAV hot water reheat configurations, must link every conditioning delivery, and must serve the whole building. ComStock chooses ERV or HRV from the climate zone; when the audit records an `Energy recovery ventilator`, the gem's `modify_existing_heat_recovery` (`comstock_erv`) then sets ComStock's ERV effectiveness on every heat exchanger. Mixed HRV and ERV records fall back, and audited effectiveness values are not transferred. Stand-alone or local-air recovery falls back.

Recognized but not yet mapped (always fall back): Packaged Rooftop VAV with Electric Reheat, VAV with Electric Reheat, Water Loop Heat Pump, Ground Source Heat Pump, Chilled Beam, and hydronic radiant systems.

BOSS also falls back when:

- any selected `HVACSystem` does not match a supported configuration;
- there is not exactly one conditioning configuration, or there is more than one ventilation configuration;
- ventilation is paired with a conditioning type that does not allow it;
- the template is not supported;
- a system's premises are scoped to specific zones rather than the whole building (the baseline binds topologies to all model zones only).

On fallback, BOSS uses the `system_type` mapping below with `add_hvac` set to `true`, and logs a warning explaining why.

#### Central furnace with cooling-only PTACs

An HVACSystem whose heating and cooling are delivered separately maps to the gem's `hvac_heating_with_terminal_cooling` measure (`heating_source` `central_gas_furnace`). This is read from standard BuildingSync elements only:

- one Delivery with `CentralAirDistribution` that references only a gas `Furnace` HeatingSource (`HeatingMedium` `Air`);
- one Delivery with `ZoneEquipment` that references only a CoolingSource whose `DXSystemType` is `Packaged terminal air conditioner (PTAC)`;
- both serve the same premises. A `MechanicalVentilation` record without a `VentilationType` linked only to these deliveries is treated as an annotation.

The heating-only Delivery may instead be `ZoneEquipment/Convection` with `ConvectionType` `Perimeter baseboard`, heated by `ElectricResistance` (`electric_baseboard`) or by a `SourceHeatingPlantID` whose plant has `Boiler/BoilerType` `Hot water` (`hot_water_baseboard`, `boiler_fuel` from the plant `PrimaryFuel`). A single `ZoneEquipment` Delivery that references both the PTAC CoolingSource and such a hot-water HeatingSource maps to `hot_water_ptac_coil`.

See `Example_NYC_Energy_Efficiency_Report_Property_2_l200.xml`, which restates the user-defined fields of `Example_NYC_Energy_Efficiency_Report_Property_2.xml` as standard elements. BOSS writes `baseline/hvac_mapping_report.json` with the plan status, the HVAC steps, and the messages. Add `--require_l200` (`require_l200: true`) to raise an error instead of falling back.

```bash
bundle exec boss write_baseline_osw my_buildingsync.xml -o ./output_dir --require_l200
```

Integration simulations currently cover the packaged rooftop heat pump, with and without recovery (`Example_ASHRAE_L2_Report_l200_erv.xml`, an edited derivative of `Example_ASHRAE_L2_Report.xml`); the other configurations are covered by unit specs.

## OpenStudio Compatibility Version

| OpenStudio Version | BuildingSync Version | BOSS Version |
|-------------------|---------------|----------|
| 3.10  | 2.7.0 | Initial Version |


## L100 Audit Workflow

The following section describes the data extracted from a BuildingSync XML file and applied to the OpenStudio model via measures, as well as the list of measures used to create the OpenStudio workflow.

### Measures used to translate L100 Audit XML file to an OpenStudio model
[set_run_period]: https://github.com/NatLabRockies/openstudio-common-measures-gem/blob/v0.12.3/lib/measures/set_run_period/README.md
[ChangeBuildingLocation]: https://github.com/NatLabRockies/openstudio-common-measures-gem/blob/v0.12.3/lib/measures/ChangeBuildingLocation/README.md
[create_bar_from_building_type_ratios]: https://github.com/NatLabRockies/openstudio-model-articulation-gem/blob/v0.12.2/lib/measures/create_bar_from_building_type_ratios/README.md
[create_typical_building_from_model]: https://github.com/NatLabRockies/openstudio-model-articulation-gem/blob/v0.12.2/lib/measures/create_typical_building_from_model/README.md
[SetLightingLoadsByLPD]: https://github.com/NatLabRockies/openstudio-common-measures-gem/blob/v0.12.3/lib/measures/SetLightingLoadsByLPD/README.md
[set_electric_equipment_loads_by_epd]: https://github.com/NatLabRockies/openstudio-common-measures-gem/tree/v0.12.3/lib/measures/set_electric_equipment_loads_by_epd
[openstudio_results]: https://github.com/NatLabRockies/openstudio-common-measures-gem/blob/v0.12.3/lib/measures/openstudio_results/README.md

The table below maps in detail the BuildingSync XML data to measure inputs. Note that this is not always a one-to-one relationship. In the table below:

- read `.../Facility` as `/BuildingSync/Facilities/Facility`
- read `.../Systems` as `/BuildingSync/Facilities/Facility/Systems`
- read `.../Site` as `/BuildingSync/Facilities/Facility/Sites/Site`
- read `.../Building` as `/BuildingSync/Facilities/Facility/Sites/Site/Buildings/Building`

| Measure                                | Argument                | set by function in BuildingSyncReader                            | Read from BuildingSync                                                                                                             |
|----------------------------------------|-------------------------|-------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| [set_run_period]                       |                         |                                           |                                                                                                                                   |
|                                        | timesteps_per_hour      |                                           | Hard Coded to `4`                                                                                                                 |
|                                        | begin_date              |                                           | Hard Coded to `2019-01-01`                                                                                                        |
|                                        | end_date                |                                           | Hard Coded to `2019-12-31`                                                                                                        |
| [ChangeBuildingLocation]               |                         |                                           |                                                                                                                                   |
|                                        | weather_file_name       | get_epw_file_path                         | either `...Site/Address/City` and  `.../Site/Address/Sate` or requirements for `get_climate_zone` |
|                                        | climate_zone            | get_climate_zone                          | either `.../Site/ClimateZoneType/ASHRAE/ClimateZone` or `.../Site/ClimateZoneType/CaliforniaTitle24/ClimateZone` depending on standard |
| [create_bar_from_building_type_ratios] |                         |                                           |                                                                                                                                   |
|                                        | bldg_type_a             | get_building_type_and_bar_division_method | `.../Building/OccupancyClassification` + requirements for `get_total_floor_area` (+ requirements for `get_floor_above_grade` lest defaulted to 1 + requirements for `get_floor_below_grade` lest defaulted to 0)   |
|                                        | total_bldg_floor_area   | get_total_floor_area                      | at least one entry of `/FloorArea` in either `.../Building/FloorAreas/` or `.../Site/FloorAreas/` (Building is used when both have one), with `FloorAreaType` of "Gross", "Conditioned", "Common", "Heated and Cooled", "Heated Only", "Cooled Only", "Conditioned above grade", or "Conditioned below grade"                                                    |
|                                        | floor_height            | get_floor_to_floor_height                 | at least on entry of `.../Building/Sections/Section` with entry `/FloorToFloorHeight`                           |
|                                        | num_stories_above_grade | get_floor_above_grade                     | either `.../Building/FloorsAboveGrade` or `.../Building/ConditionedFloorsAboveGrade` and `.../Building/UnconditionedFloorsAboveGrade`                                |
|                                        | num_stories_below_grade | get_floor_below_grade                     | either `.../Building/FloorsBelowGrade` or `.../Building/ConditionedFloorsBelowGrade` and `.../Building/UnconditionedFloorsBelowGrade`                                 |
|                                        | building_rotation       |                                           |                                                                                   |
|                                        | template                | get_standard_template                     | either `.../Building/YearOfLastMajorRemodel` or `.../Building/YearOfConstruction`                                                |
|                                        | ns_to_ew_ratio          | get_aspect_ratio                          | `.../Building/AspectRatio`                                                          |
|                                        | story_multiplier_method |                                           | Hard Coded to to None                                                                                                                       |
| [create_typical_building_from_model]   |                         |                                           |                                                                                                                                   |
|                                        | template                | get_standard_template                     | either `.../Building/YearOfLastMajorRemodel` or `.../Building/YearOfConstruction`                                                |
|                                        | system_type             | get_principal_HVAC_system_type            | at least one mappable entry of `.../Systems/HVACSystems/HVACSystem/PrincipalHVACSystemType`                                                                                  |
|                                        | add_swh                 |                                           | Hard Coded to to true                                                                                  |
|                                        | add_hvac                |                                           | `true` for fallback baselines; `false` when an HVAC topology is applied (see [Baseline HVAC](#baseline-hvac))                                                                                  |
| [SetLightingLoadsByLPD]                |                         |                                           |                                                                                                                                   |
|                                        | lpd                     | get_total_installed_power                 | `/InstalledPower` in ALL instances of `.../Systems/LightingSystems/LightingSystem`                                                                                   |
| [set_electric_equipment_loads_by_epd]  |                         |                                           |                                                                                                                                   |
|                                        | epd                     | get_total_weighted_average_load           | `/WeightedAverageLoad` in ALL instances of `.../Systems/PlugLoads/PlugLoad`                                                    |
| [openstudio_results]                   |                         |                                                                                                                                   |


## CLI Usage (`boss_cli`)

The repo includes a Thor-based CLI in `lib/boss_cli.rb`, registered as the `boss` executable in the gemspec.

From the repository root, run:

```bash
bundle exec boss help
```

### Commands

```bash
bundle exec boss write_baseline_osw BUILDINGSYNC_FILE -o OUTPUT_PATH [options]
bundle exec boss run_osw BUILDINGSYNC_FILE -o OUTPUT_PATH [options]
```

To get help text, type the following:
```bash
bundle exec boss help [COMMAND]
```

### Options

- `-o`, `--output_path` (required): directory where BOSS writes output (for example, use an XML-specific folder such as `output/v2.7.0/L100_Audit-1.0.0`)
- `-w`, `--epw_path` (optional): path to a weather `.epw` file, relative to the current working directory or absolute; BOSS stores it as an absolute path in the generated OSW. If omitted, BOSS derives weather from the BuildingSync file when possible
- `-v`, `--standard_version` (optional): modeling standard used by BOSS, such as `ASHRAE90.1` or `CaliforniaTitle24` (defaults to `ASHRAE90.1`)
- `-r`, `--run` (optional, `write_baseline_osw` only): run the baseline workflow after writing the OSW

### CLI Example: Write a baseline OSW

This example uses a BuildingSync fixture already in the repo:

```bash
bundle exec boss write_baseline_osw \
    "spec/files/v2.7.0/L100_Audit-1.0.0.xml" \
    -o output/v2.7.0/L100_Audit-1.0.0
```

### CLI Example: Write and run with an explicit weather file

```bash
bundle exec boss write_baseline_osw \
    "spec/files/v2.7.0/Chula_Vista_ASHRAE_L2_Example_Building.xml" \
    -o output/v2.7.0/Chula_Vista_ASHRAE_L2_Example_Building \
    -v ASHRAE90.1 \
    -w weather/USA_CA_Chula.Vista-Brown.Field.Muni.AP.722904_TMY3.epw \
    -r
```

### CLI Example: Run an existing baseline OSW

Use this when `output/v2.7.0/L100_Audit-1.0.0/baseline/in.osw` already exists:

```bash
bundle exec boss run_osw \
    -o output/v2.7.0/L100_Audit-1.0.0
```

### Notes

- If your file path contains spaces, wrap it in quotes.
- The baseline OSW is written under `output_path/baseline/in.osw`.

Example: 
```bash
bundle exec boss write_baseline_osw "spec/files/v2.7.0/L100_Audit-1.0.0.xml" -o output/v2.7.0/L100_Audit-1.0.0
```

## Tests

Integration tests need the external measures installed first:

```bash
bundle exec rake measures:install_external
```

Run the full suite (unit + all integration simulations):

```bash
bundle exec rake
```

Run only the fast unit tests:

```bash
bundle exec rspec spec/tests/unit
```

Run the integration smoke subset (2 simulations):

```bash
BOSS_SMOKE=1 bundle exec rspec spec/tests/integration
```

Run one shard of the full integration suite (here shard 0 of 4, as in CI):

```bash
BOSS_SHARD=0 BOSS_SHARDS=4 bundle exec rspec spec/tests/integration
```

In CI, unit tests run on every pull request. The full integration suite (4 parallel shards) also runs on every pull request, except documentation-only changes (`*.md`, `docs/`, `LICENSE`) or pull requests labeled `skip-integration`. It always runs on pushes to `develop`, tags, nightly, and on manual dispatch.
