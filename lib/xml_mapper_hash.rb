class XmlMapper
  class XmlMapperHash < Hash
    attr_accessor :xml_path, :node

    def self.from_path_and_node(new_path, new_node)
      hash = self.new
      hash.xml_path = new_path
      hash.node = new_node
      hash
    end
    
    def clone_attributes_into!(to_be_cloned_attributes, into_keys)
      hashes_from_into_keys(into_keys).each do |sub_attributes|
        [to_be_cloned_attributes].flatten.each do |clone_key, clone_value|
          sub_attributes[clone_key.to_sym] ||= self[clone_key.to_sym] if self.has_key?(clone_key.to_sym)
        end
      end
    end
    
    def hashes_from_into_keys(into_keys)
      [into_keys].flatten.map { |key| self[key] }.flatten.compact
    end
    
    def strip_attributes!(hash)
      hash.each do |key, value|
        if value.is_a?(Hash)
          strip_attributes!(value)
        elsif value.is_a?(Array)
          value.map { |array_value| strip_attributes!(array_value) }
        elsif value.respond_to?(:strip!)
          value.strip!
          hash[key] = nil if value.length == 0
        end
      end
    end
  end
end
