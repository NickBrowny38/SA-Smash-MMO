module MultiplayerVersion
  MAJOR = 0
  MINOR = 1
  PATCH = 7

  VERSION  =  "#{MAJOR}.#{MINOR}.#{PATCH}"

  def self.compare(version1, version2)
    v1_parts = version1.to_s.split('.').map(&:to_i)
    v2_parts = version2.to_s.split('.').map(&:to_i)

    while v1_parts.length < 3
      v1_parts << 0
    end
    while v2_parts.length < 3
      v2_parts << 0
    end

    3.times do |i|
      if v1_parts[i] < v2_parts[i]
        return -1
      elsif v1_parts[i] > v2_parts[i]
        return 1
      end
    end

    return 0
  end

  def self.compatible?(client_version, server_version)
    client_parts  =  client_version.to_s.split('.').map(&:to_i)
    server_parts = server_version.to_s.split('.').map(&:to_i)

    return client_parts[0] == server_parts[0]
  end

  def self.meets_requirement?(client_version, min_required_version)
    return compare(client_version, min_required_version) >= 0
  end
end

puts "[Multiplayer] Version #{MultiplayerVersion::VERSION} loaded"
