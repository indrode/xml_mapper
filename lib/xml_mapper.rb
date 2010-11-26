require "nokogiri"

class XmlMapper
  attr_accessor :mappings, :after_map_block, :within_xpath
  
  class << self
    attr_accessor :mapper
    
    def text(*args)
      mapper.add_mapping(:text, *args)
    end
    
    def integer(*args)
      mapper.add_mapping(:integer, *args)
    end
    
    def boolean(*args)
      mapper.add_mapping(:boolean, *args)
    end
    
    def exists(*args)
      mapper.add_mapping(:exists, *args)
    end
    
    def node(*args)
      mapper.add_mapping(:node, *args)
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
      self.superclass && self.superclass.respond_to?(:mapper) ? self.superclass.mapper.send(method, xml) : {}
    end
    
    def attributes_from_xml_path(path)
      attributes_from_superclass(path, :attributes_from_xml_path).merge(mapper.attributes_from_xml_path(path))
    end
    
    def capture_submapping(&block)
      saved_mapper = self.mapper
      self.mapper = XmlMapper.new
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
      args.first.map { |xpath, key|  add_single_mapping(type, xpath, key, options) }
    else
      args.map { |arg| add_single_mapping(type, arg, arg, options) }
    end
  end
  
  def after_map(&block)
    self.after_map_block = block
  end
  
  def add_single_mapping(type, xpath, key, options = {})
    self.mappings << { :type => type, :xpath => add_with_to_xpath(xpath), :key => key, :options => options }
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
    elsif mapping[:type] == :exists
      !doc.at("//#{mapping[:xpath]}").nil?
    else
      value = mapping[:type] == :node ? doc.at(mapping[:xpath]) : inner_text_for_xpath(doc, mapping[:xpath])
      apply_after_map_to_value(value, mapping)
    end
  end
  
  def apply_after_map_to_value(value, mapping)
    after_map = TYPE_TO_AFTER_CODE[mapping[:type]]
    after_map ||= mapping[:options][:after_map]
    if value && after_map
      value = value.send(after_map)  if value.respond_to?(after_map)
      value = self.send(after_map, value) if self.respond_to?(after_map)
    end
    value
  end
  
  def inner_text_for_xpath(doc, xpath)
    if node = doc.at(xpath)
      node.inner_text
    end
  end
  
  MAPPINGS = {
    "true" => true,
    "false" => false,
    "yes" => true,
    "y" => true,
    "n" => false
  }
  
  def string_to_boolean(value)
    MAPPINGS[value.to_s.downcase]
  end
end