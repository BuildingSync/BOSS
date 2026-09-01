# Scenario Workflow Translation Plan

This plan tracks the work needed for BOSS to translate BuildingSync package scenarios into OpenStudio workflows. PRs 1-4 are covered by the current PR. Future PRs should stay small and follow the roadmap below.

## Goal

BOSS should keep writing and running the baseline workflow it supports today, then add scenario workflows for BuildingSync `PackageOfMeasures` scenarios.

The first scenario release should:

- Find package scenarios under `Reports/Report/Scenarios/Scenario/ScenarioType/PackageOfMeasures`.
- Resolve each package `MeasureID` against `Facilities/Facility/Measures/Measure`.
- Map supported BuildingSync measures to OpenStudio measure steps with a BOSS-owned JSON map.
- Write `baseline/in.osw` plus one scenario OSW for each package scenario with at least one mapped measure.
- Run baseline and scenario OSWs through `OpenStudio::Extension::Runner`.
- Warn about skipped or unmapped measures without failing the whole translation.

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

Each scenario OSW should deep-copy the baseline workflow and append mapped retrofit steps. This keeps every scenario runnable on its own and makes parallel runs possible later.

## Mapping Rules

Mappings should live in:

```text
lib/BOSS/scenario_measure_map.json
```

Lookup order:

1. `SystemCategoryAffected` plus `MeasureName`.
2. Technology category element plus `MeasureName`, when `SystemCategoryAffected` is missing or not useful.

The legacy `../BuildingSync-gem` mapping can be used as background, but do not copy it directly. Every measure directory and argument added to BOSS must be checked against the OpenStudio gems declared in `BOSS.gemspec`.

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
- Delivered by: Current PR #5 branch
- Scope: Add this plan and set the first-release boundaries.
- Done when: The plan explains PR order, acceptance gates, mapping ownership, warnings, scenario selection, and result-writeback scope.
- Avoid: Leaving scope or ownership ambiguous.

### PR 2: Scenario Data Model And Discovery

- Status: Done
- Delivered by: Current PR #5 branch
- Scope: Add reader-returned structures for first-facility report-level package scenarios.
- Done when: Unit tests show `building_151.xml` discovers baseline plus package scenarios and existing reader behavior remains unchanged.
- Avoid: Hardcoded namespaces, wrong scenario paths, or reader regressions.

### PR 3: Measure Index

- Status: Done
- Delivered by: Current PR #5 branch
- Scope: Index first-facility measures by ID and extract category, name, linked premises, cost/savings, and implementation metadata.
- Done when: Tests resolve package `MeasureID` references in `building_151.xml` to parsed measure metadata.
- Avoid: Silently dropping unresolved refs or crashing on measures without `TechnologyCategories`.

### PR 4: Parser Warning Contract

- Status: Done
- Delivered by: Current PR #5 branch
- Scope: Add structured parser warnings for missing IDs, unresolved refs, empty packages, missing names, missing categories, and packages with no usable measures.
- Done when: Tests cover warning cases using `BuildingEQ-1.0.0.xml`, `Golden Test File.xml`, and no-measure fixtures.
- Avoid: Warnings that only print to stdout or malformed package data that aborts all discovery.

### PR 5: Initial Mapping JSON

- Status: Planned
- Delivered by: -
- Scope: Add `lib/BOSS/scenario_measure_map.json` with a small verified mapping set from `building_151.xml`.
- Done when: The JSON is valid and each entry has a source category/name, target `measure_dir_name`, and arguments.
- Avoid: Copying legacy mappings without checking current measure directories and arguments.

### PR 6: Basic `ScenarioMeasureMapper`

- Status: Planned
- Delivered by: -
- Scope: Load the JSON, normalize lookup keys, and map one parsed BuildingSync measure to OpenStudio step specs by `SystemCategoryAffected` plus `MeasureName`.
- Done when: Unit tests return expected steps and structured unmapped warnings.
- Avoid: Mutating reader data, raising on unmapped measures, or hardcoding mapping rules outside JSON.

### PR 7: Technology Category Fallback

- Status: Planned
- Delivered by: -
- Scope: Add fallback lookup by technology category plus `MeasureName`.
- Done when: Tests prove fallback works when `SystemCategoryAffected` is missing and normal lookup priority still wins.
- Avoid: Changing normal category/name lookup behavior.

### PR 8: Conditional Mapping Rules

- Status: Planned
- Delivered by: -
- Scope: Add data-driven conditional arguments for building type and principal HVAC/system context.
- Done when: Tests prove conditions include and exclude arguments predictably.
- Avoid: Per-measure Ruby condition chains.

### PR 9: Structured Mapping Results

- Status: Planned
- Delivered by: -
- Scope: Return mapped steps, skipped measure IDs, warnings, and scenario write/skip status.
- Done when: Scenarios with mapped measures are writable and zero-mapped scenarios are skipped with clear warnings.
- Avoid: Requiring callers to infer status from logs or empty arrays.

### PR 10: Baseline OSW Builder Refactor

- Status: Planned
- Delivered by: -
- Scope: Move baseline writing into an internal builder while preserving public behavior.
- Done when: Existing baseline integration tests pass and generated baseline steps are unchanged.
- Avoid: Unexpected API, CLI, or baseline output changes.

### PR 11: Scenario OSW Writer API

- Status: Planned
- Delivered by: -
- Scope: Add an API that writes baseline plus scenario OSWs for package scenarios with at least one mapped measure.
- Done when: Generation tests show expected directories and skipped-scenario reporting.
- Avoid: Writing OSWs for zero-mapped scenarios or changing baseline output.

### PR 12: Scenario Workflow Step Assembly

- Status: Planned
- Delivered by: -
- Scope: Deep-copy baseline OSW and append mapped retrofit steps in deterministic order.
- Done when: OSW tests assert baseline steps plus expected mapped measure steps and arguments.
- Avoid: Mutating the baseline OSW, omitting baseline creation steps, or using nondeterministic step order.

### PR 13: Generic OSW Step Helpers

- Status: Planned
- Delivered by: -
- Scope: Centralize mapped step appending and `OpenStudio::Extension.set_measure_argument` use.
- Done when: Tests prove boolean, numeric, and string arguments serialize correctly.
- Avoid: Broad rewrites of baseline populator methods or unintended baseline JSON changes.

### PR 14: Generalized Runner

- Status: Planned
- Delivered by: -
- Scope: Run `baseline/in.osw` and `scenarios/**/in.osw` while keeping `run_baseline_osw` intact.
- Done when: Tests or smoke runs show the correct OSW list and baseline-only compatibility.
- Avoid: Running skipped or missing OSWs, or removing baseline-only behavior.

### PR 15: CLI Command

- Status: Planned
- Delivered by: -
- Scope: Add a Thor command for baseline plus package scenarios using existing output, weather, standard, and run options.
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
- Delivered by: Current PR #5 branch
- Handoff: `BOSS::BuildingSyncReader#get_report_scenarios` returns first-facility report scenarios as symbol-keyed hashes with `scenario_id`, `scenario_name`, `temporal_status`, `report_id`, `scenario_type`, `package_id`, `reference_case_id`, `measure_ids`, and `linked_premises_idrefs`.
- Handoff: `BOSS::BuildingSyncReader#get_package_measure_scenarios` filters those records to package-of-measures scenarios. PR 3 should use `measure_ids` to resolve package references against facility measures.
- Verification: `bundle exec rspec spec/tests/unit/buildingsync_reader_spec.rb` - 22 examples, 0 failures.
- Verification: `bundle exec rspec spec/tests/integration/write_and_run_osws_spec.rb` - 19 examples, 1 unrelated Windows path-quoting failure; 18 baseline runs completed successfully.
- Follow-up: PR 3 should add facility measure indexing. Warning contracts stay deferred to PR 4.

### PR 3: Measure Index

- Status: Done
- Delivered by: Current PR #5 branch
- Handoff: `BOSS::BuildingSyncReader#get_measures` returns first-facility measures as a hash keyed by `Measure/@ID`. Values include `measure_id`, `system_category_affected`, `technology_category_element_name`, `measure_name`, `custom_measure_name`, `linked_premises_idrefs`, useful cost/savings fields, and `implementation_status`.
- Handoff: Missing optional fields return `nil` or `[]`. Missing `Measures` returns `{}`. Measures without `TechnologyCategories` remain parseable.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit/buildingsync_reader_spec.rb` - 29 examples, 0 failures.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rubocop --only Lint/UnreachableLoop lib/BOSS/buildingsync_reader/buildingsync_reader.rb` - no offenses.
- Follow-up: PR 4 should report unresolved `MeasureID` references and incomplete measure metadata without changing reader return shapes unless needed for the warning contract.

### PR 4: Parser Warning Contract

- Status: Done
- Delivered by: Current PR #5 branch
- Handoff: `BOSS::BuildingSyncReader#get_parser_warnings` returns symbol-keyed warning hashes with `code`, `severity`, `message`, and relevant scenario/package/measure context. Existing scenario and measure reader return shapes remain unchanged.
- Handoff: Warning codes cover missing scenario/package/measure IDs, missing `MeasureID` references, unresolved measure references, packages without `MeasureID` references, packages with no parser-usable measures, and resolved measures missing `SystemCategoryAffected`, technology category, or `MeasureName`.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rspec spec/tests/unit/buildingsync_reader_spec.rb` - 33 examples, 0 failures.
- Verification: `C:\Ruby32-x64\bin\ruby.exe -S bundle exec rubocop lib/BOSS/buildingsync_reader/buildingsync_reader.rb spec/tests/unit/buildingsync_reader_spec.rb` - still reports existing style debt and new-cop configuration warnings.
- Follow-up: PR 5 can add mapping JSON. Mapping-specific warnings remain PR 6/PR 9 scope.

## Verification Commands

Use the narrowest command that proves the current PR. Broaden only when the change justifies it.

```bash
bundle exec rspec spec/tests/unit/buildingsync_reader_spec.rb
bundle exec rspec spec/tests/unit/scenario_measure_mapper_spec.rb
bundle exec rspec spec/tests/integration/write_and_run_osws_spec.rb
bundle exec rake
```
