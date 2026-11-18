# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'json'
require 'BOSS/osw_arg_populator'

RSpec.describe OSWArgPopulator do
  def round_trip(osw)
    JSON.parse(JSON.pretty_generate(osw), symbolize_names: true)
  end

  def results_step
    { measure_dir_name: 'openstudio_results', arguments: { __SKIP__: false } }
  end

  describe '.set_step_argument' do
    it 'serializes boolean, numeric, and string arguments without coercion' do
      osw = { steps: [] }
      step = described_class.append_step(osw, { measure_dir_name: 'm', arguments: {} })
      {
        'on' => true, 'off' => false, 'zero' => 0, 'count' => 4, 'ratio' => 0.6,
        'text' => 'Inferred', 'empty' => '', 'numeric_text' => '4', 'boolean_text' => 'false'
      }.each { |name, value| described_class.set_step_argument(step, name, value) }

      arguments = round_trip(osw)[:steps].first[:arguments]
      expect(arguments).to eq(
        on: true, off: false, zero: 0, count: 4, ratio: 0.6,
        text: 'Inferred', empty: '', numeric_text: '4', boolean_text: 'false'
      )
      expect(arguments[:count]).to be_an Integer
      expect(arguments[:ratio]).to be_a Float
    end

    it 'updates only the given step when other steps share its measure_dir_name' do
      osw = { steps: [] }
      baseline = described_class.append_step(osw, { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { lpd: 1.0 } })
      first = described_class.append_step(osw, { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { lpd: 0.6 } })
      described_class.append_step(osw, { measure_dir_name: 'SetLightingLoadsByLPD', arguments: { lpd: 0.5 } })

      described_class.set_step_argument(first, 'lpd', 0.4)
      described_class.set_step_argument(baseline, '__SKIP__', false)

      expect(osw[:steps].map { |step| step[:arguments] }).to eq [
        { lpd: 1.0, __SKIP__: false }, { lpd: 0.4 }, { lpd: 0.5 }
      ]
      expect(osw[:steps].map { |step| step.key?(:name) }).to all(be false)
    end
  end

  describe '.append_step' do
    it 'appends at the end by default and keeps prepopulated argument types' do
      osw = { steps: [results_step] }
      described_class.append_step(osw, { measure_dir_name: 'm', arguments: { flag: true, n: 2, x: 1.5, s: '0.50' } })

      steps = round_trip(osw)[:steps]
      expect(steps.map { |step| step[:measure_dir_name] }).to eq ['openstudio_results', 'm']
      expect(steps.last[:arguments]).to eq(flag: true, n: 2, x: 1.5, s: '0.50')
    end

    it 'inserts before the named measure in call order, or appends when it is absent' do
      osw = { steps: [{ measure_dir_name: 'a', arguments: {} }, results_step] }
      described_class.append_step(osw, { measure_dir_name: 'b', arguments: {} }, before_measure: 'openstudio_results')
      described_class.append_step(osw, { measure_dir_name: 'c', arguments: {} }, before_measure: 'openstudio_results')
      described_class.append_step(osw, { measure_dir_name: 'd', arguments: {} }, before_measure: 'missing')

      expect(osw[:steps].map { |step| step[:measure_dir_name] }).to eq ['a', 'b', 'c', 'openstudio_results', 'd']
    end

    it 'adds an arguments hash when the step has none' do
      osw = { steps: [] }
      expect(described_class.append_step(osw, { measure_dir_name: 'm' })).to eq(measure_dir_name: 'm', arguments: {})
    end

    it 'stores independent copies of the source step' do
      source = { measure_dir_name: 'm', arguments: { s: 'value' } }
      osw = { steps: [] }
      first = described_class.append_step(osw, source)
      second = described_class.append_step(osw, source)

      first[:arguments][:s] << '-changed'
      described_class.set_step_argument(second, 'n', 1)

      expect(source).to eq(measure_dir_name: 'm', arguments: { s: 'value' })
      expect(osw[:steps]).to eq [
        { measure_dir_name: 'm', arguments: { s: 'value-changed' } },
        { measure_dir_name: 'm', arguments: { s: 'value', n: 1 } }
      ]
    end
  end
end
