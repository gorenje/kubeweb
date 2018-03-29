module ViewHelpers
  def perc(what,value,limits)
    return -1 if limits.nil? or limits[what.to_s].nil?
    max = limits[what.to_s].to_i
    ((value / max.to_f) * 100).to_i
  end

  def header_row(line)
    (line + " Actions").split(SpcRE).map { |v| "<th>#{v.capitalize}</th>" }.join("\n")
  end

  def cell(value)
    o = value =~ /^([0-9]+)(m|Mi|Gi|%|d|h|Ki)/ ? Nrm.call($1,$2) : value
    "<td data-order='#{o}'>#{value}</td>"
  end

  def line_to_row(line,idx)
    (c = line.split(SpcRE)).map { |v| cell(v) }.join("\n") + "<td>" +
      ["delete", "log", "desc", "scale", "shell", "restart"].map do |v|
      "<a class='_#{v}' href='#{request.path}/#{c[0]}/#{c[1]}/#{v}'>#{v}</a>"
    end.join("\n") + "</td>"
  end

  def gh(n,v)
    { :name => n, :value => v }
  end
end
