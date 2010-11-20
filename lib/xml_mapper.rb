require "nokogiri"

class XmlMapper
  attr_accessor :mappings, :after_map_block
  
  class << self
    def text(*args)
      mapper.add_mapping(:text, *args)
    end
    
    def integer(*args)
      mapper.add_mapping(:integer, *args)
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
      mapper.attributes_from_xml(xml)
    end
    
    def attributes_from_xml_path(path)
      mapper.attributes_from_xml_path(path)
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
      @mapper ||= XmlMapper.new
    end
    
    def mapper=(new_mapper)
      @mapper = new_mapper
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
    self.mappings << { :type => type, :xpath => xpath, :key => key, :options => options }
  end
  
  def attributes_from_xml_path(path)
    attributes_from_xml(File.read(path)).merge(:xml_path => path)
  end
  
  def attributes_from_xml(xml_or_doc)
    if xml_or_doc.is_a?(Array)
      xml_or_doc.map { |doc| attributes_from_xml(doc) } 
    else
      doc = xml_or_doc.is_a?(Nokogiri::XML::Node) ? xml_or_doc : Nokogiri::XML(xml_or_doc)
      atts = self.mappings.inject({}) do |hash, mapping|
        value = nil
        if mapping[:type] == :many
          value = mapping[:options][:mapper].attributes_from_xml(doc.search(mapping[:xpath]).to_a)
        else
          value = inner_text_for_xpath(doc, mapping[:xpath])
          after_map = mapping[:type] == :integer ? :to_i : nil
          after_map ||= mapping[:options][:after_map]
          if value && after_map
            value = value.send(after_map)  if value.respond_to?(after_map)
            value = self.send(after_map, value) if self.respond_to?(after_map)
          end
        end
        hash.merge(mapping[:key] => value)
      end
      atts.instance_eval(&self.after_map_block) if self.after_map_block
      atts
    end
  end
  
  def inner_text_for_xpath(doc, xpath)
    if node = doc.at(xpath)
      node.inner_text
    end
  end
end