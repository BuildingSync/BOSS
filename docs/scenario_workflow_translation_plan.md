# Scenario Workflow Translation Plan

This plan tracks the work needed for BOSS to translate BuildingSync package scenarios into OpenStudio workflows. Roadmap PRs land on the `scenario-workflow` integration branch. Merge `scenario-workflow` into `develop` once the feature is usable end to end (after PR 14A-14E and PR 15-18). Future PRs should stay small and follow the roadmap below.

## Goal

BOSS should keep writing and running the baseline workflow it supports today, then add scenario workflows for BuildingSync `PackageOfMeasures` scenarios.

The first scenario release should:

- Find package scenarios under `Reports/Report/Scenarios/Scenario/ScenarioType/PackageOfMeasures`.
- Resolve each package `MeasureID` against `Facilities/Facility/Measures/Measure`.
- Map supported BuildingSync measures to OpenStudio measure steps with a BOSS-owned JSON map.
- Write `baseline/in.osw` plus one scenario OSW for each package scenario with at least one mapped measure.
- Run baseline and scenario OSWs through `OpenStudio::Extension::Runner`.
- Warn about skipped or unmapped measures without failing the whole translation.
- Build baseline HVAC and map HVAC retrofits with the split `buildingsync-measures-gem` HVAC measures when BuildingSync data supports an exact match (PR 14A-14E). Otherwise keep the existing baseline HVAC path and warn.

## Out Of Scope For The First Release

The first release should not:

- Write simulation results back into BuildingSync XML.
- Add full multi-facility or multi-site selection.
- Introspect every OpenStudio measure argument at runtime.
- Treat reported savings or costs as simulation inputs unless a mapping explicitly says to do so.
- Require user-supplied mapping files.

## Current BOSS Anchors

- Baseline writing starts in `BOSS::Boss.write_baseline_osw` in `lib/BOSS/boss.rb`.
- Baseline execution starts in `BOSS::Boss.run_baseline_osw` in `lib/BOSS/boss.rb`.
- BuildingSync XML parsing is in `BOSS::BuildingSyncReader` in `lib/BOSS/buildingsync_reader/buildingsync_reader.rb`.
- Baseline OpenStudio steps are assembled in `lib/BOSS/osw_arg_populator.rb`.
- The CLI is Thor-based in `lib/boss_cli.rb`.
- Baseline integration tests live in `spec/tests/integration/write_and_run_osws_spec.rb`.

## BuildingSync Data To Read

For now, scenario translation should use the first facility, matching the current BOSS assumptions.

Read scenarios from:

```text
BuildingSync/Facilities/Facility/Reports/Report/Scenarios/Scenario
```

Read package data from:

```text
Scenario/ScenarioType/PackageOfMeasures
```

Read measures from:

```text
BuildingSync/Facilities/Facility/Measures/Measure
```

Each package scenario should expose:

- Scenario ID, name, temporal status, and source report ID.
- Package ID and reference case ID when present.
- Package `MeasureID` references.
- Linked premises references when present.

Each measure should expose:

- Measure ID.
- `SystemCategoryAffected`.
- Technology category element name.
- `MeasureName` and `CustomMeasureName`.
- Linked premises references.
- Useful cost and savings metadata.
- Implementation status.

## Output Layout

Keep the existing baseline path unchanged:

```text
<output_path>/baseline/in.osw
```

Write scenario workflows here:

```text
<output_path>/scenarios/<scenario_id>/in.osw
```

Each scenario OSW should deep-copy the baseline workflow and insert mapped retrofit steps before the trailing `openstudio_results` reporting step. This keeps every scenario runnable on its own and makes parallel runs possible later.

## Mapping Rules

Mappings should live in:

```text
lib/BOSS/scenario_measure_map.json
```

Lookup order:

1. Technology category element plus `MeasureName`.
2. `SystemCategoryAffected` plus `MeasureName`, when the technology category is blank, matches no mapping, or matches mappings with different steps.
3. Otherwise the measure is unmapped and reported as a warning. BOSS does not map by `MeasureName` alone or guess between mappings with different steps.

The legacy `../BuildingSync-gem` mapping can be used as background, but do not copy it directly.

Measure source order for new mappings:

1. `../buildingsync-measures-gem` custom BuildingSync measures, when one fits the BuildingSync measure semantics.
2. OpenStudio measure gems declared in `BOSS.gemspec`.
3. If neither has an applicable measure, add one to `buildingsync-measures-gem` instead of BOSS.

`buildingsync-measures-gem` is one measure source among several. ComStock, `openstudio-common-measures`, `openstudio-ee`, `openstudio-model-articulation`, and `openstudio-standards` stay supported. Pick the measure that fits the BuildingSync semantics; do not move existing mappings to `buildingsync-measures-gem` unless the new measure is verified as a better fit.

`buildingsync-measures-gem` is not released as a gem. BOSS loads it from a local sibling checkout (`../buildingsync-measures-gem`) configured in `config/external_measure_repos.yml`. Other sources keep their current install path.

HVAC mappings follow the upstream [HVAC Mapping and Migration Guide](https://github.com/BuildingSync/buildingsync-measures-gem/blob/develop/docs/HVAC_MAPPING_AND_MIGRATION.md): 17 topology measures (`operation` create/replace, comma-separated `target_zone_names`, `standards_template` 90.1-2013/2016/2019) plus 5 `modify_existing_*` modifiers that take exact OpenStudio object names. Do not map to the deprecated `modify_hvac`. A principal HVAC label alone is family evidence, not an exact match. Do not invent model object or zone names from BuildingSync IDs.

Verify every measure directory and argument against the source BOSS will load: the `BOSS.gemspec` gem versions, or the `buildingsync-measures-gem` commit pinned in CI. During PR 14A-14E, CI may pin an unmerged `buildingsync-measures-gem` branch commit; the upstream merge and CI ref bump are the last step of PR 14E. Outside that series, do not map to measures that exist only on an unmerged branch.

Keep relative-change mappings (for example "reduce by percentage") on relative measures. Do not swap them for absolute-target measures unless the measure skips models that already meet the target.

Conditional arguments should be data-driven. Use context from the reader, such as building type or principal HVAC system type, instead of per-measure Ruby condition chains.

## Legacy BuildingSync-gem Reference

Use `../BuildingSync-gem` only as a reference. It targets older BuildingSync and OpenStudio versions, so stale assumptions are expected.

Useful files:

- `../BuildingSync-gem/lib/buildingsync/report.rb` for report and scenario grouping.
- `../BuildingSync-gem/lib/buildingsync/scenario.rb` for scenario measure references and OSW ownership.
- `../BuildingSync-gem/lib/buildingsync/model_articulation/measure.rb` for the measure wrapper idea.
- `../BuildingSync-gem/lib/buildingsync/makers/workflow_maker.rb` for the write/run workflow shape.
- `../BuildingSync-gem/lib/buildingsync/makers/workflow_maker.json` for possible mapping seeds.

Keep result writeback from the legacy gem out of this first release unless this plan is updated.

## Warning Rules

Warnings should be structured data and should also be logged clearly. These cases are warnings, not fatal errors:

- A package has no `MeasureID` references.
- A package references an unknown measure ID.
- A measure is missing `SystemCategoryAffected`.
- A measure is missing a usable technology category.
- A measure is missing `MeasureName`.
- A measure cannot be mapped to an OpenStudio step.

If a scenario has at least one mapped measure, write its OSW and report warnings for skipped measures. If a scenario has no mapped measures, skip its OSW and report why.

## Roadmap

Use this roadmap as the tracker. Keep `Status` and `Delivered by` current when a PR lands.

### PR 1: Guiding Plan Doc

- Status: Done
- Delivered by: PR #5, merged into `scenario-workflow` on 2026-10-23
- Scope: Add this plan and set the first-release boundaries.
- Done when: The plan explains PR order, acceptance gates, mapping ownership, warnings, scenario selection, and result-writeback scope.
- Avoid: Leaving scope or ownership ambiguous.

### PR 2: Scenario Data Model And Discovery

- Status: Done
- Delivered by: PR #7, merged into `scenario-workflow` via PR #5
- Scope: Add reader-returned structures for first-facility report-level package scenarios.
- Done when: Unit tests show `building_151.xml` discovers baseline plus package scenarios and existing reader behavior remains unchanged.
- Avoid: Hardcoded namespaces, wrong scenario paths, or reader regressions.

### PR 3: Measure Index

- Status: Done
- Delivered by: PR #8, merged into `scenario-workflow` via PR #5
- Scope: Index first-facility measures by ID and extract category, name, linked premises, cost/savings, and implementation metadata.
- Done when: Tests resolve package `MeasureID` references in `building_151.xml` to parsed measure metadata.
- Avoid: Silently dropping unresolved refs or crashing on measures without `TechnologyCategories`.

### PR 4: Parser Warning Contract

- Status: Done
- Delivered by: PR #9, merged into `scenario-workflow` via PR #5
- Scope: Add structured parser warnings for missing IDs, unresolved refs, empty packages, missing names, missing categories, and packages with no usable measures.
- Done when: Tests cover warning cases using `BuildingEQ-1.0.0.xml`, `Golden Test File.xml`, and no-measure fixtures.
- Avoid: Warnings that only print to stdout or malformed package data that aborts all discovery.

### PR 5: Initial Mapping JSON

- Status: Done
- Delivered by: PR #10, merged into `scenario-workflow` via PR #5
- Scope: Add `lib/BOSS/scenario_measure_map.json` with a small verified mapping set from `building_151.xml`.
- Done when: The JSON is valid and each entry has a source category/name, target `measure_dir_name`, and arguments.
- Avoid: Copying legacy mappings without checking current measure directories and arguments.

### PR 6: Basic `ScenarioMeasureMapper`

- Status: Done
- Delivered by: `scenario-workflow-6-basic-measure-mapper` branch
- Scope: Load the JSON, normalize lookup keys, and map one parsed BuildingSync measure to OpenStudio step specs by `SystemCategoryAffected` plus `MeasureName`.
- Done when: Unit tests return expected steps and structured unmapped warnings.
- Avoid: Mutating reader data, raising on unmapped measures, or hardcoding mapping rules outside JSON.

### PR 7: Technology Category Lookup

- Status: Done
- Delivered by: `scenario-workflow-7-technology-category-fallback` branch
- Scope: Look up mappings by technology category plus `MeasureName` first, then fall back to `SystemCategoryAffected` plus `MeasureName`.
- Done when: Tests prove technology category lookup wins, `SystemCategoryAffected` fallback works when the technology category is blank, unmatched, or ambiguous, and unresolved measures warn instead of guessing.
- Avoid: Changing mapped results for `building_151.xml` measures, mapping by `MeasureName` alone, or guessing between mappings with different steps.

### PR 8: Conditional Mapping Rules

- Status: Done
- Delivered by: PR #16, merged into `scenario-workflow`
- Scope: Add data-driven conditional arguments for building type and principal HVAC/system context. Mapper engine and tests only; the PR 5 deferred production mappings are separate follow-up work.
- Done when: Tests prove conditions include and exclude arguments predictably.
- Avoid: Per-measure Ruby condition chains.

### PR 9: Structured Mapping Results

- Status: Done
- Delivered by: PR #17, merged into `scenario-workflow`
- Scope: Return mapped steps, skipped measure IDs, warnings, and scenario write/skip status.
- Done when: Scenarios with mapped measures are writable and zero-mapped scenarios are skipped with clear warnings.
- Avoid: Requiring callers to infer status from logs or empty arrays.

### PR 10: Baseline OSW Builder Refactor

- Status: Done
- Delivered by: PR #18, merged into `scenario-workflow`
- Scope: Move baseline writing into an internal builder while preserving public behavior.
- Done when: Existing baseline integration tests pass and generated baseline steps are unchanged.
- Avoid: Unexpected API, CLI, or baseline output changes.

### PR 11: Scenario OSW Writer API

- Status: Done
- Delivered by: PR #20, merged into `scenario-workflow`, combined with PR 12
- Scope: Add an API that writes baseline plus scenario OSWs for package scenarios with at least one mapped measure.
- Done when: Generation tests show expected directories and skipped-scenario reporting.
- Avoid: Writing OSWs for zero-mapped scenarios or changing baseline output.

### PR 12: Scenario Workflow Step Assembly

- Status: Done
- Delivered by: PR #20, merged into `scenario-workflow`, combined with PR 11
- Scope: Deep-copy baseline OSW and append mapped retrofit steps in a practical OpenStudio construction order, not BuildingSync `MeasureID` order. Make sure `buildingsync-measures-gem` measures are on the OSW `measure_paths`; `develop` already provides `config/external_measure_repos.yml` for this.
- Ordering: Keep the order data-driven. For example, give each mapping step a `workflow_phase` in `scenario_measure_map.json` (envelope, then internal loads, then HVAC equipment, then controls and operations) and stable-sort mapped steps by phase, breaking ties by reference order. OpenStudio already runs model measures before EnergyPlus and reporting measures, so phases only order model measures.
- Done when: OSW tests assert baseline steps plus expected mapped measure steps and arguments, and every mapped `measure_dir_name` resolves from the OSW `measure_paths`. A multi-measure package listed out of phase order produces phase-ordered steps. A test covers the LED mapping, whose `SetLightingLoadsByLPD` step also exists in the baseline, and proves the baseline step's arguments are unchanged.
- Avoid: Mutating the baseline OSW, omitting baseline creation steps, nondeterministic step order, or hardcoding phase order in Ruby per measure.

### PR 13: Generic OSW Step Helpers

- Status: Done
- Delivered by: PR #21, merged into `scenario-workflow`
- Scope: Centralize mapped step appending and `OpenStudio::Extension.set_measure_argument` use.
- Done when: Tests prove boolean, numeric, and string arguments serialize correctly.
- Avoid: Broad rewrites of baseline populator methods or unintended baseline JSON changes.

### PR 14: Generalized Runner

- Status: Done
- Delivered by: PR #23, merged into `scenario-workflow`
- Scope: Run `baseline/in.osw` and the `:written` scenario OSWs from a `write_baseline_and_scenario_osws` result while keeping `run_baseline_osw` intact. The writer result, not a `scenarios/**/in.osw` scan, selects scenarios, because the writer does not remove stale OSWs.
- Done when: Tests or smoke runs show the correct OSW list and baseline-only compatibility.
- Avoid: Running skipped, stale, or missing OSWs, or removing baseline-only behavior.

### PR 14A: Local Measure Source Support

- Status: Planned
- Delivered by: -
- Scope: Let a repo entry in `config/external_measure_repos.yml` point to a local checkout (`local_path`, relative to the manifest) instead of a Git URL. Use it for `buildingsync-measures-gem` (`../../buildingsync-measures-gem`, root `lib/measures`). Keep ComStock and gem-provided measures unchanged.
- Done when: Local sources resolve independent of CWD, BOSS runs no Git commands against them, a missing local source fails with an actionable error, and mixed-source scenario OSWs resolve every step. CI checks out `buildingsync-measures-gem` as a sibling at a recorded commit.
- Avoid: Silent fallback to `vendor/external_measures/buildingsync-measures-gem`, changing measure path precedence, or treating `buildingsync-measures-gem` as the only source.

### PR 14B: HVAC Selection Contract

- Status: In progress
- Delivered by: -
- Depends on: Can run in parallel with PR 14A.
- Scope: Read detailed HVAC data (sources, deliveries, plants, condensers, other HVAC systems, linked premises) and select topologies with the upstream guide's predicates. Shared by baseline and scenario workflows. Keep `get_principal_HVAC_system_type` for the existing baseline path.
- Done when: Table-driven tests cover exact matches and separate results for missing input, conflicting input, mapping gaps, and configurations with no gem measure.
- Avoid: Inferring topology from `MeasureName` or principal label alone, or dropping HVAC constituents silently.
- Implementation: `BOSS::HvacTopologySelector` (`lib/BOSS/hvac_topology_selector.rb`) returns one result per conditioning `Delivery` and per `OtherHVACSystem`, with status `match`, `mapping_gap`, `not_mappable`, `missing_input`, `conflicting_input`, or `no_hvac`, the `LinkedPremises` references, and a `group_key` (delivery, cooling source, plant tuple, or other-system ID). Family-only `PrincipalHVACSystemType` data returns `missing_input`.
- Deferred to later steps: guards comparing `Quantity` with zone counts and the premises-containment checks need the model crosswalk (PR 14C). Group-member consistency, zone-overlap checks, plant-binding limits, call ordering, and scenario `@Status` record selection belong to call construction (PR 14D/14E). `DuctSystems` checks are not implemented yet.
- Fixture follow-ups (found in PR 14D): a `Delivery` or `OtherHVACSystem` without its own `LinkedPremises` inherits the parent `HVACSystem` links (BuildingSync fixtures link premises only there; the upstream guide reads the record's own links). An `OtherHVACSystem` whose only content is `MechanicalVentilation` with `VentilationType` `None` or no type names no ventilation equipment; it owns its linked deliveries only when all of them are explicitly unconditioned. Otherwise those deliveries are selected as conditioning deliveries, and the record returns `no_hvac` (`None`, configuration "No separate ventilation equipment") or `missing_input` (no type). Fixture effect: ASHRAE-L2-style deliveries are now selected but return `conflicting_input`, because their `SourceHeatingPlantID` points to a plant in a different `HVACSystem` (cross-system plant references are not resolved yet). Whether the baseline planner may ignore `no_hvac` records is a PR 14D decision.
- Integrated outdoor air: an `OtherHVACSystem` with `Integration` `Integrated with central air distribution` or `Integrated with local air distribution` describes outdoor air through the linked deliveries' own air system. It does not consume those deliveries and returns the new status `integrated`; ERV, exhaust, and other not-mappable equipment still return `not_mappable`. Whether the planner may ignore `integrated` records is a PR 14D decision.
- Upstream guide rules adopted (buildingsync-measures-gem `e1b2f33`): Packaged Rooftop AC and Warm Air Furnace require a gas, air-medium `Furnace` and accept `FurnaceType` `Warm air`, `Other`, or absent. Packaged Rooftop Heat Pump accepts `HeatPumpBackupSystemFuel` `Electricity` or `Natural gas` and returns it in `Result#measure_arguments` as `supplemental_heating_fuel` (`Electricity`/`NaturalGas`). An empty `FanBasedDistributionType` counts as absent. `CS/Quantity` is a guard on the VAV and VRF rows. From `5e775a6`: packaged and terminal DX rows read an omitted `DX/CondenserPlantIDs` as air-cooled (VRF still requires it).
- L200 fixtures: `example-smalloffice-level2.xml` and `Reference-PrimarySchool-L200-Audit.xml` (copied from `../schema/docs/notebooks/bsync_examples/`) carry full Delivery/source/plant records. The L200 school now matches one Packaged Rooftop VAV with Hot Water Reheat and three Packaged Rooftop AC deliveries; VAV pods 2, 3, and other still return `conflicting_input` because they reference the `Boiler` plant defined in `VAV-Pod1` (resolving plants across `HVACSystem` records is open BOSS selector work). `example-smalloffice-level2.xml` now matches five Packaged Rooftop Heat Pump deliveries with `supplemental_heating_fuel` `NaturalGas`.
- Follow-up for PR 14C (done in PR 14C): the binder and wrapper forward `Result#measure_arguments` (for example `supplemental_heating_fuel`).

### PR 14C: Model Target Binding

- Status: In progress
- Delivered by: -
- Depends on: PR 14B.
- Scope: Bind selected BuildingSync premises to the actual OpenStudio zone and equipment names the topology and modifier measures need. OSWs are written before the model exists, so this step must prove how names are resolved at run time. A new runtime measure belongs in `buildingsync-measures-gem`, not BOSS.
- Done when: A model-based test proves exact zone/object binding, full shared-system scope for `replace`, and self-contained scenario OSWs.
- Avoid: Placeholder or guessed names, blank `target_zone_names` defaults, or making scenarios wait on baseline runs.
- Findings: BOSS baseline zones come from `create_bar_from_building_type_ratios` and carry no BuildingSync IDs, and no v2.7.0 fixture links premises on HVAC deliveries. A probe workflow showed that a measure cannot change a later OSW step's arguments at run time.
- Decision: bind whole-building premises only (`Building`, `Site`, `Facility`). `BOSS::HvacTargetBinder` (`lib/BOSS/hvac_target_binder.rb`) emits an `apply_hvac_topology_to_zone_scope` step with `zone_scope = all_model_zones`; zone, space, and section links return `missing_input`. The new upstream measure resolves every model zone by exact name at run time and runs the selected topology measure, so `replace` always gets the full zone list and scenario OSWs do not depend on a baseline run. Its Minitest suite (`apply_hvac_topology_to_zone_scope_test.rb`) covers create, full-scope replace of a shared air loop, topology safety checks, and an empty model.
- Modifier object binding: upstream `apply_hvac_modifier_to_object_scope` runs one `modify_existing_*` measure on object names resolved at run time. `object_scope = all_matching_objects` takes every object the modifier and setting can change (efficiency metric picks the coil or VRF type, `boiler_*`/`chiller_*` property picks boilers or chillers, `plant_loop_type` picks Heating/Cooling/Condenser loops); `explicit_object_names` takes `object_names_json`. Other modifier arguments pass as `modifier_arguments_json`. It fails when nothing matches and rejects names containing commas, because the modifiers split target names on commas. `HvacTargetBinder#bind_modifier` emits this step: whole-building premises give `all_matching_objects`, explicit `object_names:` give `explicit_object_names`, other premises and plant-loop changes without a loop type return `missing_input`.
- Remaining: CI pins the unmerged gem branch commit `30cdd34`, which adds `apply_hvac_modifier_to_object_scope` and `topology_arguments_json`. The upstream merge moves to the end of PR 14E. Quantity-versus-zone-count guards cannot run for whole-building scope before the model exists.
- Explicit zone scope: upstream `apply_hvac_topology_to_zone_scope` now also takes `zone_scope = explicit_zone_names` with `zone_names_json` (a JSON array, so names may contain commas), and topology measures accept JSON `target_zone_names`. `HvacTargetBinder#bind` takes optional `zone_names:` and then emits that scope for any premises. No BOSS caller passes zone names yet: generated baseline zone names are not known when the OSW is written.
- Data-derived topology arguments: upstream `apply_hvac_topology_to_zone_scope` takes an optional `topology_arguments_json` (a JSON object of string values) and passes it to the topology measure. It rejects keys the wrapper sets itself (`operation`, `target_zone_names`, `standards_template`) and arguments the topology measure does not define. `HvacTargetBinder#bind` writes non-empty `Result#measure_arguments` there, so a gas-backup packaged heat pump gets `{"supplemental_heating_fuel":"NaturalGas"}`. The CI pin must move to the gem commit that adds this argument.

### PR 14D: Baseline HVAC Integration

- Status: In progress
- Delivered by: -
- Depends on: PR 14A-14C.
- Scope: For exact-match files, run `create_typical_building_from_model` with `add_hvac: false`, then the split topology `create` steps. `add_hvac: false` also skips standards sizing and HVAC efficiency steps, so this PR must account for them. Otherwise keep the current baseline and warn (missing or family-only HVAC data, or templates other than 90.1-2013/2016/2019).
- Done when: Exact-match baselines simulate with the expected HVAC; fallback files keep their current steps and log why; baseline-only and scenario-writer baselines match.
- Avoid: Mapping DOE Ref, older 90.1, or DEER templates to 90.1-2019, or adding HVAC on top of `add_hvac: true`.
- Findings: with `add_hvac: false`, openstudio-standards 0.8.2 `create_typical_building_from_model` skips PRM sizing parameters, the sizing run, multizone VAV outdoor-air sizing, prototype HVAC assumptions, the HVAC efficiency standard, and NIST infiltration schedules; its night-cycle thermostat change then finds no managers. Topology measures do none of these. No existing measure runs this tail alone.
- Decision: `BOSS::BaselineHvacPlanner` (`lib/BOSS/baseline_hvac_planner.rb`) plans topology HVAC only when every selector result is `:match`, binds to whole-building premises, the template is 90.1-2013/2016/2019, and there is exactly one conditioning configuration plus at most one ventilation configuration (ventilation only with zone-equipment topologies, since DOAS `create` rejects air-loop zones). Steps go right after `create_typical_building_from_model`: conditioning, then ventilation, then the new upstream measure `apply_standard_hvac_sizing_and_efficiency`, which mirrors the skipped tail. Otherwise `build_baseline_osw` keeps `add_hvac: true` and logs each reason. When topology steps are used, the baseline adds the scenario-only `buildingsync-measures-gem` measure path. Baseline-only and scenario writers share `build_baseline_osw`.
- Current fixture effect (after the 14B selector follow-ups): none; every v2.7.0 fixture still falls back. Many also fail the template gate first (`DOE Ref`, `90.1-2007`, or no standard). With the template gate bypassed, the first HVAC reason is: family-only `PrincipalHVACSystemType` data (L100 files, `building_151_level1`, `example-smalloffice-level1`, `all_measures_applied_example`, BETTER); HVACSystems the selector sees without Delivery/OtherHVACSystem records (most ASHRAE-L2-style, Chula Vista, NYC, San Francisco, HOMES, Golden Test File, ASHRAE 211 Export); heat/energy-recovery ventilation (`not_mappable`: BuildingEQ, `Example_ASHRAE_L2_Report`); and detailed data that matches no known configuration (`Reference-PrimarySchool-L200-Audit`, `Example_NYC_Energy_Efficiency_Report_Property_2`). `example-smalloffice-level2` now fails only the template gate (see below). The gaps behind these are listed in `docs/hvac_mapping_gaps.md`.
- Follow-up: delivery premises inheritance and `None`/untyped ventilation handling landed in 14B and did not unlock a fixture.
- Configuration merging: the planner treats results with the same measure and `measure_arguments` as one configuration, whatever their group keys. Its premises count as whole-building (one `apply_hvac_topology_to_zone_scope` step with `all_model_zones`) when every link is a `Section` of the single `Building` and the links include its `Whole building` section or every other non-empty section. Partial section coverage still returns `missing_input`.
- First topology fixture: `example-smalloffice-level2` now plans topology HVAC except for the template gate (built 2000, so `DOE Ref 1980-2004`). The test-only copy `spec/files/v2.7.0/example-smalloffice-level2-built-2012.xml` sets `YearOfConstruction` and `YearOfLastMajorRemodel` to 2012 (`90.1-2013`, the oldest supported template). It plans one Packaged Rooftop Heat Pump step with `{"supplemental_heating_fuel":"NaturalGas"}`, then the sizing step. Future work: resolve every construction year, not just 2010 and later, instead of relying on the copy.
- Remaining: `apply_standard_hvac_sizing_and_efficiency` is on the pinned gem branch commit `30cdd34` (its Minitest covers arguments and input checks only; the sizing path needs EnergyPlus); the upstream merge moves to the end of PR 14E. Add a baseline simulation check on the 2012 copy to meet "simulate with the expected HVAC".

### PR 14E: Scenario HVAC Mappings

- Status: Planned
- Delivered by: -
- Depends on: PR 14D.
- Scope: Map HVAC retrofit measures onto the steps `HvacTargetBinder` already produces (`bind` for topology `replace`, `bind_modifier` for `modify_existing_*`) through the PR 9 result contract. No new binding work belongs here. Order conditioning, then DOAS/ventilation, then modifiers. Keep existing economizer, DCV, and thermostat mappings from other gems.
- Done when: One topology replacement and one modifier case run end to end, partial shared-system replacement is rejected, and mixed-source packages still write and run.
- Avoid: Mapping "Replace boiler" or "Replace burner" to an efficiency edit, guessing values, or partial HVAC graphs.
- Series close: merge the `buildingsync-measures-gem` branch upstream (`apply_hvac_topology_to_zone_scope`, `apply_standard_hvac_sizing_and_efficiency`, and any 14E measures), replace the CI pin `bdf14e8` with the merged commit, and rerun the unit and integration suites.

### PR 15: CLI Command

- Status: Planned
- Delivered by: -
- Scope: Add a Thor command for baseline plus package scenarios using existing output, weather, standard, and run options. Run mode passes the writer result to `run_baseline_and_scenario_osws`.
- Done when: CLI help documents the command, write-only mode creates OSWs, and run mode invokes the generalized runner.
- Avoid: Changing existing `write_baseline_osw` or `run_osw` behavior.

### PR 16: User Documentation

- Status: Planned
- Delivered by: -
- Scope: Update README or user docs with scenario paths, output layout, mapping policy, warning behavior, and CLI examples.
- Done when: Docs match implemented command names and options and include one known fixture example.
- Avoid: Promising result writeback or unsupported mapping coverage.

### PR 17: Mapper Unit Test Expansion

- Status: Planned
- Delivered by: -
- Scope: Add focused mapper tests for mapped, conditional, fallback, and unmapped cases.
- Done when: Mapper behavior is covered without relying only on slow integration tests.
- Avoid: Leaving important mapper paths covered only by integration tests.

### PR 18: Scenario Generation And Integration Coverage

- Status: Planned
- Delivered by: -
- Scope: Add OSW generation tests and focused write/run integration for a small known-translatable scenario subset.
- Done when: Focused commands pass and supported scenario `out.osw` files report `completed_status: Success`.
- Avoid: Running every package scenario by default, making CI too slow, or hiding failures behind broad skips.

## Progress Tracking

Allowed status values:

- `Planned`: Not started.
- `In Progress`: Actively being implemented.
- `Done`: Delivered and `Done when` criteria are satisfied.
- `Blocked`: Waiting on a decision, dependency, or external fix.
- `Closed`: No longer needed; include the reason.

When a PR step changes:

1. Update its `Status`.
2. Update `Delivered by` with the PR number, commit SHA, or short branch note.
3. Confirm the `Done when` criteria still match the implementation.
4. Update later PRs if scope or order changed.

At the start of a future session, read this roadmap, then verify it against `git log` and the current file tree. If it is stale, fix the roadmap before starting new implementation work.

## Handoff Notes

Use this section for stable facts future PRs need. Keep entries short and tied to a PR number.

### PR 2: Scenario Data Model And Discovery

- Status: Done
- Delivered by: PR #7, merged into `scenario-workflow` via PR #5
- Handoff: `BOSS::BuildingSyncReader#get_report_scenarios` returns first-facility report scenarios as symbol-keyed hashes with `scenario_id`, `scenario_name`, `temporal_status`, `report_id`, `scenario_type`, `package_id`, `reference_case_id`, `measure_ids`, and `linked_premises_idrefs`.
- Handoff: `BOSS::BuildingSyncReader#get_package_measure_scenarios` filters those records to package-of-measures scenarios. PR 3 should use `measure_ids` to resolve package references against facility measures.
- Verification: `bundle exec rspec spec/tests/unit/buildingsync_reader_spec.rb` - 22 examples, 0 failures.
- Verification: `bundle exec rspec spec/tests/integration/write_and_run_osws_spec.rb` - 19 examples, 1 unrelated Windows path-quoting failure; 18 baseline runs completed successfully.
- Follow-up: PR 3 should add facility measure indexing. Warning contracts stay deferred to PR 4.

### PR 3: Measure Index

- Status: Done
- Delivered by: PR #8, merged into `scenario-workflow` via PR #5
- Handoff: `BOSS::BuildingSyncReader#get_measures` returns first-facility measures as a hash keyed by `Measure/@ID`. Values include `measure_id`, `system_category_affected`, `technology_category_element_name`, `measure_name`, `custom_measure_name`, `linked_premises_idrefs`, useful cost/savings fields, and `implementation_status`.
- Handoff: Missing optional fields return `nil` or `[]`. Missing `Measures` returns `{}`. Measures without `TechnologyCategories` remain parseable.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit/buildingsync_reader_spec.rb` - 29 examples, 0 failures.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rubocop --only Lint/UnreachableLoop lib/BOSS/buildingsync_reader/buildingsync_reader.rb` - no offenses.
- Follow-up: PR 4 should report unresolved `MeasureID` references and incomplete measure metadata without changing reader return shapes unless needed for the warning contract.

### PR 4: Parser Warning Contract

- Status: Done
- Delivered by: PR #9, merged into `scenario-workflow` via PR #5
- Handoff: `BOSS::BuildingSyncReader#get_parser_warnings` returns symbol-keyed warning hashes with `code`, `severity`, `message`, and relevant scenario/package/measure context. Existing scenario and measure reader return shapes remain unchanged.
- Handoff: Warning codes cover missing scenario/package/measure IDs, missing `MeasureID` references, unresolved measure references, packages without `MeasureID` references, packages with no parser-usable measures, and resolved measures missing `SystemCategoryAffected`, technology category, or `MeasureName`.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit/buildingsync_reader_spec.rb` - 33 examples, 0 failures.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rubocop lib/BOSS/buildingsync_reader/buildingsync_reader.rb spec/tests/unit/buildingsync_reader_spec.rb` - still reports existing style debt and new-cop configuration warnings.
- Follow-up: PR 5 can add mapping JSON. Mapping-specific warnings remain PR 6/PR 9 scope.

### PR 5: Initial Mapping JSON

- Status: Done
- Delivered by: PR #10, merged into `scenario-workflow` via PR #5
- Handoff: `lib/BOSS/scenario_measure_map.json` maps 12 `building_151.xml` category/name pairs to OSW-shaped steps with `measure_dir_name` and an argument hash that includes `__SKIP__`. Source strings match reader output exactly.
- Handoff: Roof and wall absolute insulation targets use `buildingsync-measures-gem` `modify_envelope_insulation` with SI R-values (R-30 IP = 5.28, R-25 IP = 4.40 m²K/W). Other mappings use `openstudio-ee` or `openstudio-common-measures`. Relative mappings such as air sealing, ceiling insulation by percentage, and thermal bypasses stay on relative measures.
- Deferred: Daylight controls, package unit replacement, burner replacement, and boiler replacement. The `buildingsync-measures-gem` split HVAC measures (`modify_existing_hvac_equipment_efficiencies`, `modify_existing_plant_equipment`, `hvac_packaged_rooftop_*`) need exact model object or zone names. Map them in a follow-up after `buildingsync-measures-gem` PR #3 merges and exact target names can be supplied; PR 8 only adds the conditional-argument engine they may use. Update: upstream PR #3 merged (`c7efd32`); this work is now PR 14A-14E.
- Verification: JSON parse passed; every mapped measure directory and argument was checked against installed `BOSS.gemspec` gems and `buildingsync-measures-gem` `develop`.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit/scenario_measure_map_spec.rb`.
- Follow-up: PR 6 adds `BOSS::ScenarioMeasureMapper`. PR 12 must put `buildingsync-measures-gem` on OSW `measure_paths`.

### PR 6: Basic `ScenarioMeasureMapper`

- Status: Done
- Delivered by: `scenario-workflow-6-basic-measure-mapper` branch
- Handoff: `BOSS::ScenarioMeasureMapper.new(map_path = SCENARIO_MEASURE_MAP_PATH)` loads the JSON once with symbol keys. `SCENARIO_MEASURE_MAP_PATH` lives in `lib/BOSS/constants.rb`. A missing file, invalid JSON, or a missing `mappings` array raises `ArgumentError`.
- Handoff: `#map_measure(measure)` takes one value from `BuildingSyncReader#get_measures` and returns `{ measure_id:, steps:, warnings: }`. Each step is a deep copy shaped `{ measure_dir_name:, arguments: { __SKIP__: false, ... } }`, in JSON order. Callers may mutate returned steps safely.
- Handoff: Lookup key is `[system_category_affected, measure_name]`, normalized with strip, squeeze spaces, and downcase. On duplicate JSON keys the first entry wins.
- Handoff: Unmapped measures never raise. They return `steps: []` and one warning shaped like reader warnings: `code`, `severity: :warning`, `message`, `measure_id`, `system_category_affected`, `measure_name`. Codes are `:measure_lookup_key_incomplete` (blank category or name) and `:unmapped_measure` (no JSON entry). Each warning is also logged via `BOSS.BOSS_logger.warn`.
- Handoff: On `building_151.xml`, 12 of 16 measures map. Measure4, Measure5, Measure6, and Measure18 return `:unmapped_measure`, matching the PR 5 deferrals.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit/scenario_measure_mapper_spec.rb` - 11 examples, 0 failures.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit` - 78 examples, 0 failures, no constant redefinition warnings.
- Verification: `bundle exec rubocop` on the changed files reports only `Layout/EndOfLine` on Windows working copies; git normalizes line endings on commit.
- Follow-up: PR 7 should handle blank `system_category_affected` by falling back to `technology_category_element_name`, which narrows `:measure_lookup_key_incomplete` to blank `measure_name` only. Superseded: PR 7 made technology category the primary lookup instead.
- Follow-up for PR 12/13: `OpenStudio::Extension.set_measure_argument` matches every step with the same `measure_dir_name` unless `step_name` is passed. `SetLightingLoadsByLPD` is both a baseline step and the LED mapping target. Append mapped steps with their arguments already set, or pass a unique `step_name`, so baseline step arguments are not overwritten.

### PR 7: Technology Category Lookup

- Status: Done
- Delivered by: `scenario-workflow-7-technology-category-fallback` branch
- Handoff: `#map_measure` looks up `[technology_category_element_name, measure_name]` first. If that key is blank, has no JSON entry, or matches entries with different steps, it looks up `[system_category_affected, measure_name]`. Otherwise the measure is unmapped. Both keys use the PR 6 normalization, and BOSS never maps by `measure_name` alone.
- Handoff: Technology category matches with identical steps collapse to one mapping. If the technology category match is ambiguous and `SystemCategoryAffected` does not resolve it, the result is `steps: []` with `:ambiguous_technology_category_mapping`. Other misses return `:unmapped_measure`. A future window-specific air sealing entry would share `BuildingEnvelopeModifications` + `Air seal envelope` with the wall entry, so `SystemCategoryAffected` would choose between them.
- Handoff: `:measure_lookup_key_incomplete` means blank `measure_name`, or both `technology_category_element_name` and `system_category_affected` blank. Mapper warnings and log lines also include `technology_category_element_name`.
- Handoff: `scenario_measure_map.json` `lookup_order` is `technology_category_element_name_and_measure_name`, then `system_category_affected_and_measure_name`. It documents the order; the mapper does not read it. Every entry must have a non-empty `technology_category_element_name`, and the 12 current values were checked against `../schema/BuildingSync.xsd` and `building_151.xml` reader output. `building_151.xml` still maps 12 of 16 measures with the same steps as PR 6.
- Handoff: Fixture outcomes: `179D_Example_Building.xml` has no `SystemCategoryAffected`; technology category lookup maps its air sealing and LED measures, and its two `ServiceHotWaterSystems` measures stay unmapped. `Fenestration` + `Air seal envelope` in `Example_ASHRAE_L2_Report_-_with_Energy_Use_Data.xml` is a window air sealing upgrade and maps through `BuildingEnvelopeModifications` to the whole-building `ReduceSpaceInfiltrationByPercentage` step. `Upgrade operating protocols, calibration, and/or sequencing` in `Example_HOMES_Template_Building.xml` with `Other HVAC`/`BuildingAutomationSystems` or `Domestic Hot Water`/`WaterAndSewerConservationSystems` matches neither key, so both stay `:unmapped_measure`.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit/scenario_measure_mapper_spec.rb spec/tests/unit/scenario_measure_map_spec.rb` - 21 examples, 0 failures.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit` - 83 examples, 0 failures.
- Verification: `bundle exec rubocop` on the changed Ruby files reports only `Layout/EndOfLine` on the Windows working copy of `scenario_measure_mapper_spec.rb`.
- Follow-up: PR 8 conditional rules must keep the technology-category-first lookup. Entries that share a technology category and `MeasureName` with different steps are allowed, but each needs a distinct `SystemCategoryAffected` so the fallback can choose one.
- Follow-up: PR 17 already has lookup priority, fallback, and ambiguity coverage from PR 7; extend it only for gaps PR 8 introduces.

### PR 8: Conditional Mapping Rules

- Status: Done
- Delivered by: PR #16, merged into `scenario-workflow`
- Handoff: `#map_measure(measure, context: {})` accepts `building_type` (first value of `BuildingSyncReader#get_building_type_and_bar_division_method`) and `hvac_system_type` (`#get_principal_HVAC_system_type`, the mapped OpenStudio name). The caller builds the context; the mapper does not read XML. `nil` context is empty; other non-Hash values raise `ArgumentError`. Extra keys are ignored. Return shape and warnings are unchanged.
- Handoff: A step may have optional `conditional_arguments`, an ordered array of `{ "when": {...}, "arguments": {...} }`. `when` keys are `building_type` and `hvac_system_type`; each value is a non-blank string or non-empty string array. All keys must match (AND); any array value may match (OR); matching uses the lookup normalization. Missing, blank, or non-string context never matches and is not a warning.
- Handoff: After PR 7 lookup selects a mapping, each step is deep-copied, `conditional_arguments` is removed, and every matching rule's arguments merge into the step arguments in JSON order. The last match wins; base arguments are defaults; unmatched conditional-only arguments are absent. Rule values must be strings, numbers, or booleans.
- Handoff: Ambiguity checks compare full step definitions including `conditional_arguments`, so entries with equal defaults but different rules do not collapse. Context never resolves category ambiguity.
- Handoff: Malformed rules raise `ArgumentError` at load with the `mappings[i].steps[j].conditional_arguments[k]` location. The shipped `scenario_measure_map.json` is unchanged and has no conditional rules yet.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit/scenario_measure_mapper_spec.rb spec/tests/unit/scenario_measure_map_spec.rb` - 29 examples, 0 failures.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit` - 91 examples, 0 failures.
- Verification: `bundle exec rubocop` on the changed Ruby files reports only `Metrics/BlockLength` on the mapper spec's top-level `describe` block.
- Follow-up: PR 11/12 should build the context from the reader once per file and pass it to `map_measure`.

### PR 9: Structured Mapping Results

- Status: Done
- Delivered by: PR #17, merged into `scenario-workflow`
- Handoff: `#map_package_scenario(scenario, measures, context: {})` takes one record from `get_package_measure_scenarios` and the `get_measures` index. It returns `scenario_id`, `scenario_name`, `report_id`, `package_id`, `status`, `steps`, `skipped_measure_ids`, and `warnings`. `status` is `:writable` when `steps` is non-empty, otherwise `:skipped`.
- Handoff: Every `MeasureID` occurrence is processed in order. Repeated references produce repeated steps, skipped IDs, and warnings. `steps` is flat, in reference order then mapping step order. This order is provisional: PR 12 reorders steps by workflow phase. Do not treat `steps` order as the final OSW order. `context` is forwarded to `map_measure` for each occurrence.
- Handoff: Blank refs warn `:missing_measure_idref`; unknown refs warn `:unresolved_measure_idref` with `measure_idref`. Mapper warnings from `map_measure` are kept and get `report_id`, `scenario_id`, and `package_id`. Skipped scenarios end with one `:package_has_no_mapped_measures` warning. Each warning is logged once.
- Handoff: Parser warnings stay in `get_parser_warnings`. Callers that combine both streams should expect overlap for blank and unresolved refs.
- Handoff: Non-Hash `scenario`, `measures`, or `context`, a non-package `scenario_type`, or non-Array `measure_ids` raise `ArgumentError`. Results are deep copies; inputs are not mutated.
- Handoff: `building_151.xml` gives 12 writable scenarios; Scenario4, Scenario5, Scenario6, and Scenario18 are skipped.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit/scenario_measure_mapper_spec.rb spec/tests/unit/scenario_measure_map_spec.rb` - 38 examples, 0 failures.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit` - 100 examples, 0 failures.
- Verification: `bundle exec rubocop` on the changed Ruby files reports only the existing `Metrics/BlockLength` on the mapper spec's top-level `describe` block.
- Follow-up: PR 11 should write OSWs only for `:writable` results and report `:skipped` results with their warnings.

### PR 10: Baseline OSW Builder Refactor

- Status: Done
- Delivered by: PR #18, merged into `scenario-workflow`
- Handoff: Private `BOSS::Boss.build_baseline_osw(bsync_reader)` returns a new, unsaved, symbol-keyed baseline OSW hash: template, all eight baseline steps, `configure_osw`, and local -> gem -> external `measure_paths`/`file_paths`. Each call parses the template again, so callers may mutate the result.
- Handoff: `write_baseline_osw` keeps its signature, XML check, reader construction, `baseline/in.osw` layout, serialization, and return value. `run_baseline_osw` and the CLI are unchanged.
- Handoff: The baseline always has eight steps, including `replace_baseline_windows` from the external comstock repo; missing data sets `__SKIP__: true` instead of removing steps. Older `spec/output` artifacts with seven steps are stale.
- Handoff: `spec/tests/unit/boss_spec.rb` pins full step lists for `building_151.xml` and `all_measures_applied_example.xml`, captured from the pre-refactor writer.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit` - 112 examples, 0 failures.
- Verification: `bundle exec rubocop` on the changed Ruby files adds only `Metrics/BlockLength` on the spec's top-level `describe`; `boss.rb` indentation offenses follow the file's existing `class << self` layout.
- Note: Baseline simulations need `bundle exec rake measures:install_external`; without comstock, OpenStudio rejects the workflow with `Cannot find measure 'replace_baseline_windows'` before and after this refactor.
- Follow-up: PR 11 should build one reader per file, call `build_baseline_osw` once, write it to `baseline/in.osw`, and deep-copy it per writable scenario.

### PR 11 + PR 12: Scenario OSW Writer And Step Assembly

- Status: Done
- Delivered by: PR #20, merged into `scenario-workflow`. Combined because the writer cannot be tested meaningfully without step assembly.
- Handoff: `BOSS::Boss.write_baseline_and_scenario_osws(xml_file_path, output_dir, epw_file_path, standard_to_be_used)` builds one reader, one baseline OSW, one mapper, and one `{ building_type:, hvac_system_type: }` context per file. It writes `baseline/in.osw` and `scenarios/<scenario_id>/in.osw`, and returns `{ baseline_osw_path:, scenario_results:, parser_warnings: }`. Each scenario result has `scenario_id`, `scenario_name`, `report_id`, `package_id`, `status` (`:written` or `:skipped`), `osw_path` (`nil` when skipped), `skipped_measure_ids`, and `warnings`. Parser warnings are also logged. `write_baseline_osw`, `run_baseline_osw`, and the CLI are unchanged.
- Handoff: Scenario IDs become directory names. IDs must match `\A[A-Za-z0-9](?:[A-Za-z0-9_.-]{0,62}[A-Za-z0-9_-])?\z` and must not be a Windows reserved device name. Otherwise the scenario is skipped with `:missing_scenario_output_id` or `:unsafe_scenario_output_id`. IDs that match case-insensitively skip every scenario in the group with `:conflicting_scenario_output_id`. Because allowed IDs are ASCII, no Unicode normalization is needed. Skipped-ID scenarios are not mapped.
- Handoff: `scenario_measure_map.json` has a top-level `workflow_phases` array (`envelope`, `internal_loads`, `hvac_equipment`, `controls_operations`), and each step has a `workflow_phase`. The mapper validates that the phases are unique and non-blank and that every step uses a declared phase. It keeps `workflow_phase` on returned steps and exposes `#workflow_phases`. Maps without `workflow_phases` are still accepted, but their steps must not carry a phase. Plug-load controls are `controls_operations` and refrigeration replacement is `internal_loads`, even though both use `ReduceElectricEquipmentLoadsByPercentage`.
- Handoff: The writer stable-sorts mapped steps by phase index, then by reference order. It strips `workflow_phase` and inserts the full step hashes before `openstudio_results`. Baseline steps, including the baseline `SetLightingLoadsByLPD`, are never modified. `set_measure_argument` is not used.
- Handoff: `config/external_measure_repos.yml` supports an optional boolean `scenario_only`. `buildingsync-measures-gem` is pinned to `c40c2ed65952a1c3bfe82bf1daa542ce5e1ee8d6` (`develop`, `lib/measures`) with `scenario_only: true`. `ExternalMeasureRepoManager#resolved_measure_directories(include_scenario_only: false)` keeps it out of baseline OSWs. Scenario OSWs append it, and its `files` path, after the baseline paths. `install_all` installs every repo.
- Handoff: Before writing anything, the writer checks that every mapped `measure_dir_name` has a `measure.rb` on the scenario `measure_paths`. If any are missing, it raises `StandardError` naming them and pointing to `bundle exec rake measures:install_external`.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit spec/tests/integration/scenario_osw_generation_spec.rb` - 128 examples, 0 failures, after `rake measures:install_external`.
- Verification: The `building_151.xml` smoke run with real installed repos wrote 12 scenario OSWs; Scenario4, Scenario5, Scenario6, and Scenario18 were skipped.
- Verification: `bundle exec rubocop` on the changed files adds no new offenses except `Metrics/BlockLength` in specs and the existing `class << self` indentation in `boss.rb`.
- Not run: Scenario simulations. These are PR 14/PR 18 scope.
- Follow-up: PR 13 can reuse the private `build_scenario_osw` / `order_scenario_steps` helpers instead of adding new appending logic. PR 14 should run only OSWs with `status: :written`.

### PR 13: Generic OSW Step Helpers

- Status: Done
- Delivered by: PR #21, merged into `scenario-workflow`
- Handoff: `OSWArgPopulator.append_step(osw, step, before_measure: nil)` deep-copies a complete step, adds an empty `arguments` hash if missing, and inserts it before the first `before_measure` step (or appends). It returns the inserted step and never adds `name` or default arguments.
- Handoff: `OSWArgPopulator.set_step_argument(step, name, value)` is the only `OpenStudio::Extension.set_measure_argument` call site. It passes a one-step workflow, so other steps with the same `measure_dir_name` (baseline `SetLightingLoadsByLPD`, repeated `ReduceElectricEquipmentLoadsByPercentage`) are untouched. Keys are symbolized by the extension; values are not coerced.
- Handoff: The eight baseline populators only swap their append/lambda setup for `step_argument_setter`; calculations, defaults, logging, and argument order are unchanged. `build_scenario_osw` appends prebuilt mapped steps through `append_step`; mapped arguments still do not go through the setter.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit spec/tests/integration/scenario_osw_generation_spec.rb` - 136 examples, 0 failures. Baseline step characterizations in `boss_spec.rb` are unchanged.
- Verification: `bundle exec rubocop` on the changed lib files drops from 156 to 100 offenses; none are new.
- Not run: Baseline simulations (`write_and_run_osws_spec.rb`); generated baseline JSON is pinned by unit specs.

### PR 14: Generalized Runner

- Status: Done
- Delivered by: PR #23, merged into `scenario-workflow`
- Handoff: `BOSS::Boss.run_baseline_and_scenario_osws(write_result)` takes the symbol-keyed result of `write_baseline_and_scenario_osws`. It submits the baseline first, then every `status: :written` scenario `osw_path` in result order, deduplicated, in one `Runner#run_osws` call. It returns the runner's failure-message array; runner exceptions propagate.
- Handoff: Skipped scenarios never run, even if an older `in.osw` exists. Scenario OSWs on disk but absent from the result are ignored; no directory is scanned. A `:written` entry whose path is missing, blank, or not a file is skipped with a `BOSS.BOSS_logger` warning.
- Handoff: A malformed result raises `ArgumentError`; a missing baseline file logs an OpenStudio error and raises `StandardError`. Neither builds a runner. The input is not mutated.
- Handoff: Baseline-first is submission order only. The runner still runs in parallel with the existing options, and scenarios do not wait on baseline success; each scenario OSW contains its own baseline construction steps.
- Handoff: `run_baseline_osw` keeps its signature, error, runner options, and return value; both runners share the private `run_osw_paths`. The CLI is unchanged.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit/boss_spec.rb` - 33 examples, 0 failures.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit spec/tests/integration/scenario_osw_generation_spec.rb` - 145 examples, 0 failures.
- Verification: `bundle exec rubocop lib/BOSS/boss.rb spec/tests/unit/boss_spec.rb` adds only the existing `class << self` indentation pattern for the new public and private methods.
- Not run: Baseline and scenario simulations. The runner is mocked in unit specs; scenario simulations are PR 18 scope.

## Verification Commands

Use the narrowest command that proves the current PR. Broaden only when the change justifies it.

```bash
bundle exec rspec spec/tests/unit/buildingsync_reader_spec.rb
bundle exec rspec spec/tests/unit/scenario_measure_mapper_spec.rb
bundle exec rspec spec/tests/integration/write_and_run_osws_spec.rb
bundle exec rake
```
