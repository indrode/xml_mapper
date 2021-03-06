require "nokogiri"
require "xml_mapper_hash"
require "date"
require "time"

class XmlMapper
  attr_accessor :mappings, :after_map_block, :within_xpath, :selector_mode

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

    def attributes_from_xml_path(path, xml = nil)
      if xml
        attributes_from_superclass(xml, :attributes_from_xml).merge(mapper.attributes_from_xml(xml, path))
      else
        attributes_from_superclass(path, :attributes_from_xml_path).merge(mapper.attributes_from_xml_path(path))
      end
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

    def selector_mode(style)
      self.mapper.selector_mode = style
    end

    def include_mapper(clazz)
      self.mapper.mappings += clazz.mapper.mappings
    end
  end

  def initialize
    self.mappings = []
    self.selector_mode = :search
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
      xml_or_doc.map { |doc| attributes_from_xml(doc, xml_path) }
    else
      doc = to_nokogiri_doc(xml_or_doc)
      doc = doc.root if doc.respond_to?(:root)
      atts = self.mappings.inject(XmlMapperHash.from_path_and_node(xml_path, doc)) do |hash, mapping|
        if (value = value_from_doc_and_mapping(doc, mapping, xml_path)) != :not_found
          add_value_to_hash(hash, mapping[:key], value)
        end
      end
      atts.instance_eval(&self.after_map_block) if self.after_map_block
      atts
    end
  end

  def to_nokogiri_doc(xml_or_doc)
    if xml_or_doc.is_a?(Nokogiri::XML::Node)
      xml_or_doc
    else
      doc = Nokogiri::XML(xml_or_doc)
      doc.remove_namespaces!
      doc
    end
  end

  # get rid of xml namespaces, quick and dirty
  def strip_xml_namespaces(xml_string)
    xml_string.gsub(/xmlns=[\"\'].*?[\"\']/, "")
  end

  def add_value_to_hash(hash, key_or_hash, value)
    if key_or_hash.is_a?(Hash)
      hash[key_or_hash.keys.first] ||= Hash.new
      add_value_to_hash(hash[key_or_hash.keys.first], key_or_hash.values.first, value)
    else
      hash.merge!(key_or_hash => value)
    end
    hash
  end

  def value_from_doc_and_mapping(doc, mapping, xml_path = nil)
    if mapping[:type] == :many
      mapping[:options][:mapper].attributes_from_xml(doc.send(self.selector_mode, mapping[:xpath]).to_a, xml_path)
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
    if node
      node.inner_text.length == 0 ? nil : node.inner_text
    end
  end

  MAPPINGS = {
    "true" => true,
    "false" => false,
    "yes" => true,
    "no" => false,
    "y" => true,
    "n" => false,
    "1" => true,
    "0" => false
  }

  def string_to_boolean(value)
    MAPPINGS[value.to_s.downcase]
  end

  def parse_duration(string)
    return string.to_i if string.match(/^\d+$/)
    string = "00:#{string}" if string.match(/^(\d+):(\d+)$/)
    string = string.to_s.gsub(/PT(\d+M.*)/,"PT0H\\1")         # insert 0H into PT3M12S, for example: PT0H3M12S
    if string.match(/^PT(\d+)H(\d+)M(\d+)S$/) || string.match(/^(\d+):(\d+):(\d+)$/)
      $1.to_i * 3600 + $2.to_i * 60 + $3.to_i
    else
      nil
    end
  end

  def parse_date(text)
    text.to_s.strip.length > 0 ? Date.parse(text.to_s.strip) : nil
  rescue
  end
end
