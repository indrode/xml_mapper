require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "XmlMapper" do
  before(:each) do
    @mapper = XmlMapper.new
  end
  
  describe "#add_mapping" do
    it "adds the correct mappings when only one symbol given" do
      @mapper.add_mapping(:text, :title)
      @mapper.mappings.should == [{ :type => :text, :xpath => :title, :key => :title, :options => {} }]
    end
    
    it "adds the correct mapping when type is not text" do
      @mapper.add_mapping(:length, :title)
      @mapper.mappings.should == [{ :type => :length, :xpath => :title, :key => :title, :options => {} }]
    end
    
    it "adds multiple mappings when more symbols given" do
      @mapper.add_mapping(:text, :first_name, :last_name)
      @mapper.mappings.should == [
        { :type => :text, :xpath => :first_name, :key => :first_name, :options => {} },
        { :type => :text, :xpath => :last_name, :key => :last_name, :options => {} },
      ]
    end
    
    it "adds mappings when mapping given as hash" do
      @mapper.add_mapping(:text, :name => :first_name)
      @mapper.mappings.should == [{ :type => :text, :xpath => :name, :key => :first_name, :options => {} }]
    end
    
    it "adds mappings with options when mapping given as symbols and last arg is hash" do
      @mapper.add_mapping(:text, :name, :born, :after_map => :to_s)
      @mapper.mappings.should == [
        { :type => :text, :xpath => :name, :key => :name, :options => { :after_map => :to_s } },
        { :type => :text, :xpath => :born, :key => :born, :options => { :after_map => :to_s } },
      ]
    end
  end
  
  describe "map text attributes" do
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
    
    it "uses mapper method defined in xml_mapper when after_map does not respond to :upcase" do
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
    
    it "also taks a nokogiri node as argument" do
      @mapper.add_mapping(:text, :artist_name)
      @mapper.attributes_from_xml(Nokogiri::XML(@xml)).should == {
        :artist_name => "Mos Def"
      }
    end
    
    it "should also takes an array of nodes as argument" do
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
    
    it "sets the xml_path" do
      @mapper.attributes_from_xml_path("/some/path.xml").should == { 
        :title => "Black on Both Sides", :xml_path => "/some/path.xml" 
      }
    end
    
    it "calls File.read with correct parameters" do
      File.should_receive(:read).with("/some/path.xml").and_return @xml
      @mapper.attributes_from_xml_path("/some/path.xml")
    end
  end
  
  describe "defining a DSL" do
    before(:each) do
      # so that we have a new class in each spec
      class_name = "TestMapping#{Time.now.to_f.to_s.gsub(".", "")}"
      str = %(
        class #{class_name} < XmlMapper
        end
      )
      eval(str)
      @clazz = eval(class_name)
    end
    
    it "sets the correct mapping for map keyword" do
      @clazz.text(:title)
      @clazz.mapper.mappings.should == [{ :type => :text, :key => :title, :xpath => :title, :options => {} }]
    end
    
    it "sets the correct mapping for text keyword" do
      @clazz.integer(:title)
      @clazz.mapper.mappings.should == [{ :type => :integer, :key => :title, :xpath => :title, :options => {} }]
    end
    
    it "allows getting attributes form xml_path" do
      File.stub(:read).and_return %(<album><title>Test Title</title></album>)
      @clazz.text(:title)
      @clazz.attributes_from_xml_path("/some/path.xml").should == {
        :title => "Test Title",
        :xml_path => "/some/path.xml"
      }
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
          { :type => :text, :key => :title, :xpath => :title, :options => {} },
          { :type => :integer, :key => :track_number, :xpath => :track_number, :options => {} },
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
  end
end
