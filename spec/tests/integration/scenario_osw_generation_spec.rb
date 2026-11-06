# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'json'
require 'tmpdir'
require 'BOSS/constants'
require 'BOSS/boss'

# Generates scenario OSWs against the real measure paths without running simulations.
# Requires `bundle exec rake measures:install_external`.
RSpec.describe 'BOSS scenario OSW generation' do
  files_dir = File.expand_path('../../files/v2.7.0', __dir__)

  before do
    allow(BOSS::BCLWeatherFileDownloader).to receive(:download_weather_file_from_city_name)
      .and_return(openstudio_weather_file_path)
  end

  def read_osw(path)
    JSON.parse(File.read(path), symbolize_names: true)
  end

  it 'writes building_151 scenario OSWs whose steps all resolve on measure_paths' do
    xml_path = File.join(files_dir, 'building_151.xml')

    Dir.mktmpdir do |dir|
      baseline_only_dir = File.join(dir, 'baseline_only')
      scenario_dir = File.join(dir, 'with_scenarios')
      BOSS::Boss.write_baseline_osw(xml_path, baseline_only_dir, nil, ASHRAE90_1)
      result = BOSS::Boss.write_baseline_and_scenario_osws(xml_path, scenario_dir, nil, ASHRAE90_1)

      expect(read_osw(result[:baseline_osw_path])).to eq read_osw(File.join(baseline_only_dir, 'baseline', 'in.osw'))

      written = result[:scenario_results].select { |scenario| scenario[:status] == :written }
      expect(written.length).to eq 12

      written.each do |scenario|
        osw = read_osw(scenario[:osw_path])
        osw[:steps].each do |step|
          found = osw[:measure_paths].any? { |path| File.file?(File.join(path, step[:measure_dir_name], 'measure.rb')) }
          expect(found).to be(true), "#{scenario[:scenario_id]}: #{step[:measure_dir_name]} not found on measure_paths"
        end
      end
    end
  end
end
