module JSON
  def self.generate(obj)
    case obj
    when Hash
      "{" + obj.map { |k, v| "\"#{k}\":#{generate(v)}" }.join(",") + "}"
    when Array
      "[" + obj.map { |v| generate(v) }.join(",") + "]"
    when String
      "\"#{obj.gsub(/"/, '\\"')}\""
    when Symbol
      "\"#{obj.to_s}\""
    when Numeric
      obj.to_s
    when TrueClass
      "true"
    when FalseClass
      "false"
    when NilClass
      "null"
    else
      "\"#{obj.to_s}\""
    end
  end

  def self.parse(str, options = {})
    return nil if str.nil? || str.empty?

    str = str.strip

    case str[0, 1]
    when "{"
      parse_object(str, options)
    when "["
      parse_array(str, options)
    when "\""
      parse_string(str)
    when "t"
      str.start_with?("true") ? true : str
    when "f"
      str.start_with?("false") ? false : str
    when 'n'
      str.start_with?("null") ? nil : str
    else

      if str =~ /^-?\d+$/
        str.to_i
      elsif str =~ /^-?\d+\.\d+$/
        str.to_f
      else
        str
      end
    end
  end

  private

  def self.parse_object(str, options = {})
    result = {}
    str = str[1..-2].strip
    return result if str.empty?

    parts = split_json(str)
    parts.each do |part|
      key, value  =  part.split(":", 2)
      next unless key && value

      key = parse_string(key.strip)
      key = key.to_sym if options[:symbolize_names]
      result[key] = parse(value.strip, options)
    end

    result
  end

  def self.parse_array(str, options = {})
    str = str[1..-2].strip
    return [] if str.empty?

    parts = split_json(str)
    parts.map { |part| parse(part.strip, options) }
  end

  def self.parse_string(str)
    if str[0, 1] == "\""
      str[1..-2].gsub(/\\"/, '"')
    else
      str
    end
  end

  def self.split_json(str)
    parts = []
    current = ""
    depth = 0
    in_string  =  false

    str.each_char do |char|
      case char
      when "\""
        in_string  =  !in_string unless (current[-1] == "\\")
        current += char
      when "{", "["
        depth += 1 unless in_string
        current += char
      when "}", "]"
        depth -= 1 unless in_string
        current += char
      when ","
        if depth == 0 && !in_string
          parts << current
          current = ""
        else
          current += char
        end
      else
        current += char
      end
    end

    parts << current unless current.empty?
    parts
  end
end

puts "Simple JSON library loaded for multiplayer support"
