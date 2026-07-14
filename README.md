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
- external repository: comstock (`measures` and `resources/measures`)

Measure path precedence is:

1. local measure roots from [config/external_measure_repos.yml](config/external_measure_repos.yml)
2. gem-provided measure directories
3. external non-gem repository measure roots from [config/external_measure_repos.yml](config/external_measure_repos.yml)

The generated `in.osw` will include these paths in order under `measure_paths`.

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

| Measure                                | Argument                | set by function in BuildingSyncReader                            | Read from buidingsync                                                                                                             |
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
|                                        | total_bldg_floor_area   | get_total_floor_area                      | at least one entry of `/FloorArea` in either `.../Site/FloorAreas/` or `.../Building/FloorAreas/`, with `FloorAreaType` of "Gross", "Conditioned", "Common", "Heated and Cooled", "Heated Only", "Cooled Only", "Conditioned above grade", or "Conditioned below grade"                                                    |
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
|                                        | add_hvac                |                                           | Hard Coded to to true                                                                                  |
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
- `-w`, `--epw_path` (optional): path to a weather `.epw` file; if omitted, BOSS derives weather from the BuildingSync file when possible
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

To run the tests you can use the Rake task:

```bash
bundle exec rake
```