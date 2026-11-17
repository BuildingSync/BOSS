module RValueAndUFactorCalculator
  def zip_envelope_data(section_ids, systems, area_path, r_value_path, u_factor_path, system_name)
    # pair systems and sections, agg data
    data_by_id = Hash.new { |h, k| h[k] = {area: 0, r_value: nil, u_factor: nil} }
    section_ids.each do |section_id|
      id = section_id.attributes["IDref"]
      data_by_id[id][:area] += section_id.elements[area_path]&.first&.to_s&.to_f
    end
    systems.each do |system|
      id = system.attributes["ID"]
      data_by_id[id][:r_value] = system.elements[r_value_path]&.first&.to_s&.to_f
      data_by_id[id][:u_factor] = system.elements[u_factor_path]&.first&.to_s&.to_f
    end

    BOSS.BOSS_logger.info("|\t|\t|\t- #{system_name} information found: #{data_by_id}")
    return data_by_id
  end

  def get_sum_weighted_by_area(data_by_id, field_to_sum, system_name)
    # check all pairs complete
    missing_data = data_by_id.filter {|key, value| value[field_to_sum.to_sym].nil?}
    # require 'pry'; binding.pry;
    if !missing_data.empty?
      BOSS.BOSS_logger.info("|\t|\t|\t  Cannot calculate weighted #{field_to_sum} as these #{system_name} do not have an #{field_to_sum}: #{missing_data.keys}")

      return nil
    # calculate weighted average
    else
      total_area = (data_by_id.map {|k, v| v[:area]}).sum
      sum = (data_by_id.map{|k, v|  v[field_to_sum.to_sym] * (v[:area] / total_area)}).sum
      BOSS.BOSS_logger.info("|\t|\t|\t  weighted average of #{field_to_sum} calculated to be #{sum}")

      return sum
    end
  end
end
