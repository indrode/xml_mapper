require "nokogiri"

class XmlMapper
  attr_accessor :mappings, :after_map_block, :within_xpath
  
  class << self
    attr_accessor :mapper
    
    [:text, :integer, :boolean, :exists, :not_exists, :node_name, :inner_text, :node, :attribute].each do |method_name|
      define_method(method_name) do |*args|
        mapper.add_mapping(method_name, *args)
      end
    end
    
    def within(xpath, &block)
      self.mapper.within_xpath ||= []
      self.mapper.within_xpath << xpath
      self.instance_eval(&block)
      self.mapper.within_xpath.pop
    end
    
    def after_map(&block)
      mapper.after_map(&block)
    end
    
    def many(*args, &block)
      sub_mapper = block_given? ? capture_submapping(&block) : nil
      add_mapper_to_args(args, sub_mapper)
      mapper.add_mapping(:many, *args)
    end
    
    def attributes_from_xml(xml)
      attributes_from_superclass(xml, :attributes_from_xml).merge(mapper.attributes_from_xml(xml))
    end
    
    def attributes_from_superclass(xml, method = :attributes_from_xml)
      if self.superclass && self.superclass.respond_to?(:mapper)
        attributes = self.superclass.mapper.send(method, xml)
        attributes.delete(:xml_path)
        attributes
      else
        {}
      end
    end
    
    def attributes_from_xml_path(path)
      attributes_from_superclass(path, :attributes_from_xml_path).merge(mapper.attributes_from_xml_path(path))
    end
    
    def capture_submapping(&block)
      saved_mapper = self.mapper
      self.mapper = self.new
      self.instance_eval(&block)
      captured_mapper = self.mapper
      self.mapper = saved_mapper
      captured_mapper
    end
    
    def add_mapper_to_args(args, mapper)
      if args.length > 1 && args.last.is_a?(Hash)
        args.last[:mapper] = mapper
      else
        args << { :mapper => mapper }
      end
    end
    
    def mapper
      @mapper ||= self.new
    end
  end
  
  def initialize
    self.mappings = []
  end
  
  def extract_options_from_args(args)
    args.length > 1 && args.last.is_a?(Hash) ? args.pop : {}
  end
  
  def add_mapping(type, *args)
    options = extract_options_from_args(args)
    if args.first.is_a?(Hash)
      if after_map_method = args.first.delete(:after_map)
        options.merge!(:after_map => after_map_method)
      end
      args.first.map { |xpath, key| add_single_mapping(type, xpath, key, options) }
    else
      args.map { |arg| add_single_mapping(type, arg, arg, options) }
    end
  end
  
  def after_map(&block)
    self.after_map_block = block
  end
  
  def add_single_mapping(type, xpath_or_attribute, key, options = {})
    mappings = { :type => type, :key => key, :options => options }
    xpath = type == :attribute ? nil : xpath_or_attribute
    if type == :attribute
      mappings[:attribute] = xpath_or_attribute.to_s
    end
    mappings[:xpath] = add_with_to_xpath(xpath)
    self.mappings << mappings
  end
  
  def add_with_to_xpath(xpath)
    [self.within_xpath, xpath].flatten.compact.join("/")
  end
  
  def attributes_from_xml_path(path)
    attributes_from_xml(File.read(path), path)
  end
  
  TYPE_TO_AFTER_CODE = {
    :integer => :to_i,
    :boolean => :string_to_boolean
  }
  
  def attributes_from_xml(xml_or_doc, xml_path = nil)
    if xml_or_doc.is_a?(Array)
      xml_or_doc.map { |doc| attributes_from_xml(doc) } 
    else
      doc = xml_or_doc.is_a?(Nokogiri::XML::Node) ? xml_or_doc : Nokogiri::XML(xml_or_doc)
      doc = doc.root if doc.respond_to?(:root)
      atts = self.mappings.inject(xml_path.nil? ? {} : { :xml_path => xml_path }) do |hash, mapping|
        hash.merge(mapping[:key] => value_from_doc_and_mapping(doc, mapping))
      end
      atts.instance_eval(&self.after_map_block) if self.after_map_block
      atts
    end
  end
  
  def value_from_doc_and_mapping(doc, mapping)
    if mapping[:type] == :many
      mapping[:options][:mapper].attributes_from_xml(doc.search(mapping[:xpath]).to_a)
    else
      node = mapping[:xpath].length == 0 ? doc : doc.xpath(mapping[:xpath]).first
      if mapping[:type] == :exists
        !node.nil?
      elsif mapping[:type] == :not_exists
        node.nil?
      else
        value = 
        case mapping[:type]
          when :node_name
            doc.nil? ? nil : doc.name
          when :inner_text
            doc.nil? ? nil : doc.inner_text
          when :node
            node
          when :attribute
            node.nil? ? nil : (node.respond_to?(:root) ? node.root : node)[mapping[:attribute]]
          else
            inner_text_for_node(node)
        end
        apply_after_map_to_value(value, mapping)
      end
    end
  end
  
  def apply_after_map_to_value(value, mapping)
    after_mappings = [TYPE_TO_AFTER_CODE[mapping[:type]], mapping[:options][:after_map]].compact
    if value
      after_mappings.each do |after_map|
        value = value.send(after_map) if value.respond_to?(after_map)
        value = self.send(after_map, value) if self.respond_to?(after_map)
      end
    end
    value
  end
  
  def inner_text_for_node(node)
    node.inner_text if node
  end
  
  MAPPINGS = {
    "true" => true,
    "false" => false,
    "yes" => true,
    "y" => true,
    "n" => false,
    "1" => true,
    "0" => false
  }
  
  def string_to_boolean(value)
    MAPPINGS[value.to_s.downcase]
  end
end