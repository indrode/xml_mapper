require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "XmlMapper" do
  def create_class(base_class = "XmlMapper")
    class_name = "TestMapping#{Time.now.to_f.to_s.gsub(".", "")}"
    str = %(
      class #{class_name} < #{base_class}
      end
    )
    eval(str)
    eval(class_name)
  end

  before(:each) do
    @mapper = XmlMapper.new
  end

  describe "#parse_duration" do
    {
      "60" => 60, "no_duration" => nil, "PT0H5M54S" => 354, "PT3M12S" => 192, "PT64M54S" => 3894,
      "00:01" => 1, "00:00:01" => 1, "00:01:01" => 61, "01:01:01" => 3661, "1:12:42" => 4362
    }.each do |duration_string, value|
      it "converts #{duration_string.inspect} to #{value}" do
        XmlMapper.new.parse_duration(duration_string).should == value
      end
    end
  end

  describe "#parse_date" do
    it "returns nil when text is blank" do
      XmlMapper.new.parse_date(" ").should be_nil
    end

    it "returns nil when text is nil" do
      XmlMapper.new.parse_date(nil).should be_nil
    end

    it "parses dates correctly" do
      XmlMapper.new.parse_date("2010-09-01").should == Date.new(2010, 9, 1)
    end

    it "returns nil when unable to parse date" do
      XmlMapper.new.parse_date("something_wrong").should be_nil
    end
  end

  describe "#add_mapping" do
    it "adds the correct mappings when only one symbol given" do
      @mapper.add_mapping(:text, :title)
      @mapper.mappings.should == [{ :type => :text, :xpath => "title", :key => :title, :options => {} }]
    end

    it "adds the correct mapping when type is not text" do
      @mapper.add_mapping(:length, :title)
      @mapper.mappings.should == [{ :type => :length, :xpath => "title", :key => :title, :options => {} }]
    end

    it "adds the correct mapping when type is node" do
      @mapper.add_mapping(:node, :title)
      @mapper.mappings.should == [{ :type => :node, :xpath => "title", :key => :title, :options => {} }]
    end

    it "adds multiple mappings when more symbols given" do
      @mapper.add_mapping(:text, :first_name, :last_name)
      @mapper.mappings.should == [
        { :type => :text, :xpath => "first_name", :key => :first_name, :options => {} },
        { :type => :text, :xpath => "last_name", :key => :last_name, :options => {} },
      ]
    end

    it "sets attribute for attribute mapping when attribute is mapped to same name" do
      @mapper.add_mapping(:attribute, :first_name)
      @mapper.mappings.should == [
        { :type => :attribute, :attribute => "first_name", :key => :first_name, :options => {}, :xpath => "" }
      ]
    end

    it "sets attribute for attribute mapping when attribute is mapped to different name" do
      @mapper.add_mapping(:attribute, :first_name => :firstname)
      @mapper.mappings.should == [
        { :type => :attribute, :attribute => "first_name", :key => :firstname, :options => {}, :xpath => "" }
      ]
    end

    it "adds mappings when mapping given as hash" do
      @mapper.add_mapping(:text, :name => :first_name)
      @mapper.mappings.should == [{ :type => :text, :xpath => "name", :key => :first_name, :options => {} }]
    end

    it "adds mappings with options when mapping given as symbols and last arg is hash" do
      @mapper.add_mapping(:text, :name, :born, :after_map => :to_s)
      @mapper.mappings.should == [
        { :type => :text, :xpath => "name", :key => :name, :options => { :after_map => :to_s } },
        { :type => :text, :xpath => "born", :key => :born, :options => { :after_map => :to_s } },
      ]
    end
  end

  describe "map attributes" do
    before(:each) do
      @xml = %(
      <album>
        <title>Black on Both Sides</title>
        <artist_name>Mos Def</artist_name>
        <track_number>7</track_number>
      </album>)
    end

    it "maps the correct inner text when node found" do
      @mapper.add_mapping(:text, :artist_name, :title)
      @mapper.attributes_from_xml(@xml).should == { :title => "Black on Both Sides", :artist_name => "Mos Def" }
    end

    it "sets value to nil when value was empty string" do
      @mapper.add_mapping(:text, :artist_name)
      @mapper.attributes_from_xml("<album><artist_name></artist_name></album>").should == { :artist_name => nil }
    end

    it "assigns found keys to nested attributes" do
      @mapper.add_mapping(:text, :artist_name => { :meta => :artist_name })
      @mapper.add_mapping(:text, :title => { :meta => :title })
      @mapper.attributes_from_xml(@xml).should == {
        :meta => {
          :artist_name => "Mos Def",
          :title => "Black on Both Sides"
        }
      }
    end

    describe "#exists" do
      it "returns true when node exists" do
        xml = %(<album><title>Black on Both Sides</title><rights><country>DE</country></rights></album>)
        root = Nokogiri::XML(xml).root
        @mapper.add_mapping(:exists, "rights[country='DE']" => :allows_streaming)
        @mapper.attributes_from_xml(xml).should == { :allows_streaming => true }
      end

      it "returns false when node does not exist" do
        xml = %(<album><title>Black on Both Sides</title><rights><country>DE</country></rights></album>)
        @mapper.add_mapping(:exists, "rights[country='FR']" => :allows_streaming)
        @mapper.attributes_from_xml(xml).should == { :allows_streaming => false }
      end
    end

    describe "#node" do
      it "returns a nokogiri node" do
        @mapper.add_mapping(:node, :title)
        @mapper.attributes_from_xml(@xml)[:title].should be_an_instance_of(Nokogiri::XML::Element)
      end

      it "returns nil when node not found" do
        @mapper.add_mapping(:node, :rgne)
        @mapper.attributes_from_xml(@xml)[:rgne].should be_nil
      end

      it "returns the correct nokogiri node" do
        @mapper.add_mapping(:node, :title)
        node = @mapper.attributes_from_xml(@xml)[:title]
        node.inner_text.should == "Black on Both Sides"
      end

      it "can be combined with after_map" do
        @mapper.add_mapping(:node, :title, :after_map => :inner_text)
        @mapper.attributes_from_xml(@xml)[:title].should == "Black on Both Sides"
      end
    end

    it "maps not found nodes to nil" do
      @mapper.add_mapping(:text, :artist_name, :version_title, :long_title)
      @mapper.attributes_from_xml(@xml).should == {
        :version_title => nil, :long_title => nil, :artist_name => "Mos Def"
      }
    end

    it "converts integers to integer when found" do
      @mapper.add_mapping(:text, :artist_name)
      @mapper.add_mapping(:integer, :track_number)
      @mapper.attributes_from_xml(@xml).should == {
        :track_number => 7, :artist_name => "Mos Def"
      }
    end

    it "does not convert nil to integer for integer type" do
      @mapper.add_mapping(:text, :artist_name)
      @mapper.add_mapping(:integer, :track_number, :set_count)
      @mapper.attributes_from_xml(@xml).should == {
        :track_number => 7, :artist_name => "Mos Def", :set_count => nil
      }
    end

    it "calls method with name type on value when found and responding" do
      @mapper.add_mapping(:text, :artist_name, :after_map => :upcase)
      @mapper.attributes_from_xml(@xml).should == {
        :artist_name => "MOS DEF"
      }
    end

    it "uses mapper method defined in xml_mapper when value does not respond to :after_map" do
      class << @mapper
        def double(value)
          value.to_s * 2
        end
      end

      @mapper.add_mapping(:text, :artist_name, :after_map => :double)
      @mapper.attributes_from_xml(@xml).should == {
        :artist_name => "Mos DefMos Def"
      }
    end

    it "allows multiple after_code mappings" do
      class << @mapper
        def double(value)
          value * 2
        end
      end
      @mapper.add_mapping(:integer, :track_number, :after_map => :double)
      @mapper.attributes_from_xml(@xml).should == {
        :track_number => 14
      }
    end

    it "allows defining a after_map mapping without ridicolous brackets" do
      @mapper.add_mapping(:string, :track_number => :num, :after_map => :to_i)
      @mapper.attributes_from_xml(@xml).should == {
        :num => 7
      }
    end

    it "uses mapper method defined in xml_mapper when value does not respond to :after_map and given as hash" do
      class << @mapper
        def double(value)
          value * 2
        end
      end
      # [{:type=>:text, :xpath=>"Graphic/ImgFormat", :key=>:image_format, :options=>{:after_map=>:double}}]
      @mapper.add_mapping(:text, { :artist_name => :name }, {:after_map => :double})
      @mapper.attributes_from_xml(@xml).should == {
        :name => "Mos DefMos Def"
      }
    end

    it "takes a nokogiri node as argument" do
      @mapper.add_mapping(:text, :artist_name)
      @mapper.attributes_from_xml(Nokogiri::XML(@xml).root).should == {
        :artist_name => "Mos Def"
      }
    end

    it "takes a nokogiri document as argument" do
      @mapper.add_mapping(:text, :artist_name)
      @mapper.attributes_from_xml(Nokogiri::XML(@xml).root).should == {
        :artist_name => "Mos Def"
      }
    end

    it "should also takes an array of nodes as argument" do
      @mapper.add_mapping(:text, :artist_name)
      @mapper.attributes_from_xml([Nokogiri::XML(@xml).root, Nokogiri::XML(@xml).root]).should == [
        { :artist_name => "Mos Def" },
        { :artist_name => "Mos Def" }
      ]
    end

    it "also takes an array of nokogiri documents as argument" do
      @mapper.add_mapping(:text, :artist_name)
      @mapper.attributes_from_xml([Nokogiri::XML(@xml), Nokogiri::XML(@xml)]).should == [
        { :artist_name => "Mos Def" },
        { :artist_name => "Mos Def" }
      ]
    end

    describe "mapping embedded attributes" do
      before(:each) do
        @xml = %(
          <album>
            <artist_name>Mos Def</artist_name>
            <tracks>
              <track>
                <track_number>1</track_number>
                <title>Track 1</title>
              </track>
              <track>
                <track_number>2</track_number>
                <title>Track 2</title>
              </track>
            </tracks>
          </album>
        )
      end

      it "maps all embedded attributes" do
        submapper = XmlMapper.new
        submapper.add_mapping(:integer, :track_number)
        submapper.add_mapping(:text, :title)
        @mapper.add_mapping(:text, :artist_name)
        @mapper.add_mapping(:many, { "tracks/track" => :tracks }, :mapper => submapper)
        @mapper.attributes_from_xml(@xml).should == {
          :artist_name => "Mos Def",
          :tracks => [
            { :title => "Track 1", :track_number => 1 },
            { :title => "Track 2", :track_number => 2 },
          ]
        }
      end
    end
  end

  describe "#attributes_from_xml_path" do
    before(:each) do
      @mapper.add_mapping(:text, :title)
      @xml = %(
        <album>
          <title>Black on Both Sides</title>
        </album>
      )
      File.stub(:read).and_return @xml
    end

    it "calls File.read with correct parameters" do
      File.should_receive(:read).with("/some/path.xml").and_return @xml
      @mapper.attributes_from_xml_path("/some/path.xml")
    end

    it "allows using the xml_path in after_map block" do
      @mapper.after_map do
        self[:new_xml_path] = self.xml_path
      end
      @mapper.attributes_from_xml_path("/some/path.xml")[:new_xml_path].should == "/some/path.xml"
    end

    it "allows deleting the xml_path in after_map block" do
      @mapper.after_map do
        self.delete(:xml_path)
      end
      @mapper.attributes_from_xml_path("/some/path.xml").should_not have_key(:xml_path)
    end
  end

  describe "#after_map" do
    before(:each) do
      @mapper.after_map do
        self[:upc] = "1234"
      end
    end

    it "assigns after_map block" do
      @mapper.after_map_block.should_not be_nil
    end

    it "assigns a block to after_map_block" do
      @mapper.after_map_block.should be_an_instance_of(Proc)
    end

    it "should executes after_map block after mapping" do
      @mapper.attributes_from_xml("<album><title>Some Titel</title></album>").should == {
        :upc => "1234"
      }
    end

    describe "using xml_path and node" do
      before(:each) do
        xml = %(
          <album>
            <tracks>
              <track><title>First Track</title></track>
              <track><title>Second Track Track</title></track>
            </tracks>
          </album>
        )
        File.stub(:read).and_return xml
      end

      it "allows accessing xml_path in after_map block" do
        @mapper.after_map do
          self[:new_path] = self.xml_path
        end
        @mapper.attributes_from_xml_path("/some/other/path.xml").should == { :new_path => "/some/other/path.xml" }
      end

      it "allows using node in after_map block" do
        @mapper.after_map do
          self[:tracks_count] = self.node.search("tracks/track").count
        end
        @mapper.attributes_from_xml_path("/some/other/path.xml").should == { :tracks_count => 2 }
      end

      it "allows using xml_path in subnodes" do
        clazz = create_class
        clazz.many "tracks/track" => :tracks do
          after_map do
            self[:new_path] = self.xml_path
          end
        end
        clazz.attributes_from_xml_path("/some/other/path.xml").should == { :tracks =>
          [
            { :new_path => "/some/other/path.xml" },
            { :new_path => "/some/other/path.xml" }
          ]
        }
      end

      it "allows using node in subnodes" do
        clazz = create_class
        clazz.many "tracks/track" => :tracks do
          after_map do
            self[:title_count] = self.node.search("title").count
          end
        end
        clazz.after_map do
          self[:title_count] = self.node.search("title").count
        end

        clazz.attributes_from_xml_path("/some/other/path.xml").should == { :title_count => 2,
          :tracks => [
              { :title_count => 1 },
              { :title_count => 1 }
          ]
        }
      end
    end
  end

  describe "converting strings" do
    describe "#string_to_boolean" do
      {
        "true" => true, "false" => false, "y" => true, "TRUE" => true, "" => nil, "YES" => true, "yes" => true,
        "n" => false, "1" => true, "0" => false, "No" => false, "NO" => false
      }.each do |value, result|
        it "converts #{value.inspect} to #{result}" do
          @mapper.string_to_boolean(value).should == result
        end
      end
    end
  end

  describe "defining a DSL" do
    before(:each) do
      # so that we have a new class in each spec
      @clazz = create_class
    end

    it "initializes a mapper of the same class" do
      @clazz.mapper.class.name.should == @clazz.name
    end

    it "sets the correct mapping for text keyword" do
      @clazz.text(:title)
      @clazz.mapper.mappings.should == [{ :type => :text, :key => :title, :xpath => "title", :options => {} }]
    end

    it "sets the correct mapping for node keyword" do
      @clazz.node(:title)
      @clazz.mapper.mappings.should == [{ :type => :node, :key => :title, :xpath => "title", :options => {} }]
    end

    it "sets the correct mapping for text keyword" do
      @clazz.integer(:title)
      @clazz.mapper.mappings.should == [{ :type => :integer, :key => :title, :xpath => "title", :options => {} }]
    end

    it "allows getting attributes form xml_path" do
      File.stub(:read).and_return %(<album><title>Test Title</title></album>)
      @clazz.text(:title)
      @clazz.attributes_from_xml_path("/some/path.xml").should == {
        :title => "Test Title"
      }
    end

    it "allows providing of custom xml on second parameter of attributes_from_xml_path" do
      data = %(<album><title>Static Test</title></album>)
      @clazz.text(:title)
      @clazz.after_map do
        self[:some_path] = xml_path
      end
      @clazz.attributes_from_xml_path("/some/path.xml", data).should == {
        :title => "Static Test", :some_path => "/some/path.xml"
      }
    end

    it "allows defining a after_map block" do
      @clazz.after_map do
        self[:upc] = "1234"
      end
      @clazz.text(:title)
      @clazz.attributes_from_xml(%(<album><title>Test Title</title></album>)).should == {
        :upc => "1234", :title => "Test Title"
      }
    end

    it "allows deleteing the xml path in after_block" do
      @clazz.after_map do
        self.delete(:xml_path)
      end
      File.stub(:read).and_return %(<album><title>Test Title</title></album>)
      @clazz.attributes_from_xml_path("/some/path.xml").should_not have_key(:xml_path)
    end

    it "allows using attributes from superclass in after_map block"

    it "allows using of instance methods of mapper for after_map" do
      @clazz.class_eval do
        def custom_mapper(txt)
          txt * 2
        end
      end

      @clazz.text(:title, :after_map => :custom_mapper)
      @clazz.attributes_from_xml(%(<album><title>Test</title></album>)).should == {
        :title => "TestTest"
      }
    end

    it "allows after map when used in submapper and method exists in mapper" do
      xml = %(
        <album>
          <tracks>
            <track>
              <track_number>11</track_number>
            </track>
            <track>
              <track_number>22</track_number>
            </track>
          </tracks>
        </album>
      )
      @clazz.send(:define_method, "double") do |*args|
        args.first * 2
      end

      @clazz.many "tracks/track" => :tracks do
        integer :track_number => :num, :after_map => :double
      end
      @clazz.attributes_from_xml(xml).should == {
        :tracks => [ { :num => 22 }, { :num => 44 }]
      }
    end

    it "accepts boolean as keyword" do
      @clazz.boolean(:allows_streaming)
      xml = %(<album><title>Test Title</title><allows_streaming>true</allows_streaming></album>)
      @clazz.attributes_from_xml(xml).should == { :allows_streaming => true }
    end

    it "accepts exists as keyword" do
      @clazz.exists("rights[country='DE']" => :allows_streaming)
      xml = %(<album><title>Black on Both Sides</title><rights><country>DE</country></rights></album>)
      @clazz.attributes_from_xml(xml).should == { :allows_streaming => true }
    end

    it "accepts not_exists as keyword" do
      @clazz.not_exists("forbidden_countries/country[text()='DE']" => :allows_streaming)
      xml = %(<album><title>Black on Both Sides</title><forbidden_countries><country>DE</country></rights></album>)
      @clazz.attributes_from_xml(xml).should == { :allows_streaming => false }
    end

    it "does keep scope for not_exists" do
      xml = %(
        <album>
          <tracks>
            <track>
              <title>Track 1</title>
              <forbidden_countries>
                <country>DE</country>
              </forbidden_countries>
            </track>
            <track>
              <title>Track 2</title>
              <forbidden_countries>
                <country>AT</country>
              </forbidden_countries>
            </track>
          </tracks>
        </album>
      )
      @clazz.many "tracks/track" => :tracks do
        text :title
        not_exists "forbidden_countries/country[text()='DE']" => :allows_streaming
      end
      @clazz.attributes_from_xml(xml)[:tracks].should == [
        { :title => "Track 1", :allows_streaming => false },
        { :title => "Track 2", :allows_streaming => true },
      ]
    end

    describe "#within" do
      it "adds the within xpath to all xpath mappings" do
        @clazz.within("artist") do
          text :name => :artist_name
          integer :id => :artist_id
        end
        @clazz.mapper.mappings.should == [
          { :type => :text, :xpath => "artist/name", :key => :artist_name, :options => {} },
          { :type => :integer, :xpath => "artist/id", :key => :artist_id, :options => {} },
        ]
      end

      it "adds all nested within xpaths to xpath mappings" do
        @clazz.within("contributions") do
          within "artist" do
            text :name => :artist_name
            integer :id => :artist_id
          end
        end
        @clazz.mapper.mappings.should == [
          { :type => :text, :xpath => "contributions/artist/name", :key => :artist_name, :options => {} },
          { :type => :integer, :xpath => "contributions/artist/id", :key => :artist_id, :options => {} },
        ]
      end

      it "allows multiple within blocks on same level" do
        @clazz.within "artist" do
          text :name => :artist_name
        end
        @clazz.within "file" do
          text :file_name
        end
        @clazz.mapper.mappings.should == [
          { :type => :text, :xpath => "artist/name", :key => :artist_name, :options => {} },
          { :type => :text, :xpath => "file/file_name", :key => :file_name, :options => {} },
        ]
      end
    end

    describe "with mapper hierarchy" do
      it "attributes_from_xml includes superclass mapper as well" do
        @clazz.text(:artist_name)
        subclazz = create_class(@clazz.name)
        subclazz.text(:title)
        xml = %(
          <album>
            <artist_name>Mos Def</artist_name>
            <title>Black on Both Sides</title>
          </album>
        )
        subclazz.attributes_from_xml(xml).should == {
          :artist_name => "Mos Def",
          :title => "Black on Both Sides"
        }
      end

      it "overwrites superclass mapper" do
        @clazz.text(:artist_name)
        subclazz = create_class(@clazz.name)
        subclazz.text(:title)
        subclazz.text(:artist_name, :after_map => :upcase)
        xml = %(
          <album>
            <artist_name>Mos Def</artist_name>
            <title>Black on Both Sides</title>
          </album>
        )
        subclazz.attributes_from_xml(xml).should == {
          :artist_name => "MOS DEF",
          :title => "Black on Both Sides"
        }
      end

      it "attributes_from_xml_path includes superclass mapper as well" do
        @clazz.text(:artist_name)
        subclazz = create_class(@clazz.name)
        subclazz.text(:title)
        xml = %(
          <album>
            <artist_name>Mos Def</artist_name>
            <title>Black on Both Sides</title>
          </album>
        )
        File.stub!(:read).and_return xml
        subclazz.attributes_from_xml_path("/some_path/album.xml").should == {
          :artist_name => "Mos Def",
          :title => "Black on Both Sides"
        }
      end
    end

    describe "defining a submapper" do
      before(:each) do
        @clazz.many("tracks/track" => :tracks) do
          text :title
          integer :track_number
        end
      end

      it "sets the mapping type to many" do
        @clazz.mapper.mappings.first[:type].should == :many
      end

      it "sets the mapping key to track" do
        @clazz.mapper.mappings.first[:key].should == :tracks
      end

      it "sets the mapping xpath to tracks/track" do
        @clazz.mapper.mappings.first[:xpath].should == "tracks/track"
      end

      it "sets the correct submapper" do
        @clazz.mapper.mappings.first[:options][:mapper].mappings.should == [
          { :type => :text, :key => :title, :xpath => "title", :options => {} },
          { :type => :integer, :key => :track_number, :xpath => "track_number", :options => {} },
        ]
      end

      it "attributes_from_xml returns the correct attributes" do
        @clazz.text(:artist_name)
        @clazz.text(:title)
        xml = %(
          <album>
            <artist_name>Mos Def</artist_name>
            <title>Black on Both Sides</title>
            <tracks>
              <track>
                <title>Track 1</title>
                <track_number>1</track_number>
              </track>
              <track>
                <title>Track 2</title>
                <track_number>2</track_number>
              </track>
            </tracks>
          </album>
        )
        @clazz.attributes_from_xml(xml).should == {
          :artist_name => "Mos Def", :title => "Black on Both Sides",
          :tracks => [
            { :title => "Track 1", :track_number => 1 },
            { :title => "Track 2", :track_number => 2 }
          ]
        }
      end
    end


    describe "using node_name, inner_text and attribute" do
      it "extracts attributes for a many relationship when node_name and inner_text is used" do
        xml = %(
          <album>
            <Contributors>
              <Performer>Sexy sushi</Performer>
              <Composer>Sexi Sushi</Composer>
              <Author>Sexi Sushi</Author>
            </Contributors>
          </album>
        )
        @clazz.many "Contributors/*" => :contributions do
          node_name :contribution_type
          inner_text :name
        end
        @clazz.attributes_from_xml(xml).should == {
          :contributions => [
            { :contribution_type => "Performer", :name => "Sexy sushi" },
            { :contribution_type => "Composer", :name => "Sexi Sushi" },
            { :contribution_type => "Author", :name => "Sexi Sushi" },
          ]
        }
      end

      it "extracts the correct attributes when attribute keyword is used in 'many'-mapping" do
        xml = %(
          <album>
            <tracks>
              <track some_code="1234">
                <title>Track 1</title>
              </track>
            </tracks>
          </album>
        )
        @clazz.many "tracks/track" => :tracks do
          attribute "some_code" => :isrc
          text :title
        end
        @clazz.attributes_from_xml(xml).should == {
          :tracks => [
            { :isrc => "1234", :title => "Track 1" }
          ]
        }
      end

      it "extracts the correct attributes when attribute is used in within-mapping" do
        xml = %(
          <album>
            <meta code="1234">
              <title>Product Title</title>
            </meta>
          </></album>
        )
        @clazz.within "meta" do
          attribute "code" => :upc
        end
        @clazz.attributes_from_xml(xml)[:upc].should == "1234"
      end

      it "extracts the correct attributes when attribute is used in root mapping" do
        xml = %(
          <album code="1234">
            <title>Product Title</title>
          </></album>
        )
        @clazz.attribute :code => :upc
        @clazz.attributes_from_xml(xml)[:upc].should == "1234"
      end
    end
  end

  describe "#include_mapper" do
    before(:each) do
      @clazz = create_class
    end

    class Submapper < XmlMapper
      text :title, :released_on
    end

    it "is callable" do
      @clazz.include_mapper(Submapper)
    end

    it "works" do
      xml = %(
        <album>
          <artist_name>Mos Def</artist_name>
          <title>Black on Both Sides</title>
          <released_on>2011-03-01</released_on>
        </album>
      )
      @clazz.text "artist_name" => :artist_name
      @clazz.include_mapper(Submapper)
      @clazz.attributes_from_xml(xml).should == { :artist_name => "Mos Def", :title => "Black on Both Sides", :released_on => "2011-03-01" }
    end

    it "works for many keyword" do
      xml = %(
        <album>
          <title>Album Title</title>
          <released_on>1999-01-01</released_on>
          <tracks>
            <track>
              <title>Track 1</title>
              <released_on>1999-02-01</released_on>
            </track>
            <track>
              <title>Track 2</title>
              <released_on>1999-03-01</released_on>
            </track>
          </tracks>
        </album>
      )
      @clazz.many "tracks/track" => :tracks do
        include_mapper Submapper
      end
      @clazz.attributes_from_xml(xml).should ==  {
        :tracks=>[
          {
            :released_on=>"1999-02-01", :title=>"Track 1"}, {:released_on=>"1999-03-01", :title=>"Track 2"}
        ]
      }
    end
  end

  it "does not care about xmlns" do
    xml = %(
      <submission xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xsi:schemaLocation="http://schemas.ingrooves.com/INgrooves/INgrooves_2_0.xsd http://schemas.ingrooves.com/INgrooves/INgrooves_2_0.xsd" schema_version="1" schema_revision="0" xmlns="http://schemas.ingrooves.com/INgrooves/INgrooves_2_0.xsd">
        <album>
          <title>Black on Both Sides</title>
        </album>
      </submission>
    )
    class Mapper < XmlMapper
      within "album" do
        text "title" => :title
      end
    end

    Mapper.attributes_from_xml(xml).should == { :title => "Black on Both Sides" }
  end

  it "also removes xmlsns not ending with xsd" do
    xml = %(
      <product xmlns="http://www.fuck.com/you/umg">
        <album>
          <title>Some Title</title>
        </album>
      </product>
    )
    class Mapper < XmlMapper
      within "album" do
        text "title" => :title
      end
    end

    Mapper.attributes_from_xml(xml).should == { :title => "Some Title" }
  end

  it "allows forcing xpath style selectors" do
    mapper = create_class.new
    mapper.add_mapping(:many, { "tracks/track" => :tracks }, :mapper => XmlMapper.new)
    mapper.selector_mode = :xpath
    node = mock("nokogiri node")
    node.stub(:remove_namespaces!)
    node.should_receive(:send).with(:xpath, "tracks/track")
    Nokogiri.stub(:XML).and_return {node}
    xml = %(
          <album>
            <title>Black on Both Sides</title>
          </album>
    )
    mapper.attributes_from_xml(xml)
  end
end
