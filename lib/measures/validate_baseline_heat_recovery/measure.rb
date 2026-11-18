# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

# Fails the workflow unless every air loop with outdoor air has exactly one air-to-air
# heat exchanger with nonzero sensible effectiveness.
class ValidateBaselineHeatRecovery < OpenStudio::Measure::ModelMeasure
  def name
    'Validate Baseline Heat Recovery'
  end

  def description
    'Checks that every outdoor-air air loop has exactly one usable air-to-air heat exchanger.'
  end

  def modeler_description
    'Postcondition for BOSS L200 baselines that request exhaust-air recovery. Counts HeatExchangerAirToAirSensibleAndLatent ' \
      'objects on each AirLoopHVAC outdoor air system and requires a nonzero sensible effectiveness.'
  end

  def arguments(_model)
    OpenStudio::Measure::OSArgumentVector.new
  end

  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)
    return false if !runner.validateUserArguments(arguments(model), user_arguments)

    loops = model.getAirLoopHVACs.select { |air_loop| air_loop.airLoopHVACOutdoorAirSystem.is_initialized }
    if loops.empty?
      runner.registerError('No air loop with an outdoor air system; recovery cannot be validated.')
      return false
    end

    errors = loops.filter_map { |air_loop| loop_error(air_loop) }
    runner.registerValue('heat_recovery_loops_checked', loops.length)
    runner.registerValue('heat_recovery_loops_valid', loops.length - errors.length)
    if !errors.empty?
      errors.each { |error| runner.registerError(error) }
      return false
    end

    runner.registerFinalCondition("All #{loops.length} outdoor-air loops have one heat exchanger.")
    true
  end

  private

  def loop_error(air_loop)
    oa_system = air_loop.airLoopHVACOutdoorAirSystem.get
    exchangers = (oa_system.oaComponents + oa_system.reliefComponents)
                 .filter_map { |c| c.to_HeatExchangerAirToAirSensibleAndLatent.then { |hx| hx.get if hx.is_initialized } }
                 .uniq(&:handle)
    return "#{air_loop.name} has #{exchangers.length} heat exchangers; expected 1." if exchangers.length != 1

    exchanger = exchangers.first
    effectiveness = [exchanger.sensibleEffectivenessat100HeatingAirFlow, exchanger.sensibleEffectivenessat100CoolingAirFlow]
    return "#{air_loop.name} heat exchanger #{exchanger.name} has zero sensible effectiveness." if !effectiveness.all?(&:positive?)

    nil
  end
end

ValidateBaselineHeatRecovery.new.registerWithApplication
