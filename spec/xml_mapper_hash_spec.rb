require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe XmlMapper::XmlMapperHash do
  describe "#from_path_and_node" do
    it "sets the correct xml_path" do
      hash = XmlMapper::XmlMapperHash.from_path_and_node("/some/path.xml", nil)
      hash.xml_path.should == "/some/path.xml"
    end
    
    it "sets the correct node" do
      node = double("node")
      hash = XmlMapper::XmlMapperHash.from_path_and_node("/some/path.xml", node)
      hash.node.should == node
    end
  end
  
  describe "#clone_attributes_into" do
    it "does not break when track_attributes are nil" do
      hash = XmlMapper::XmlMapperHash.new.merge(:upc => "1234")
      hash.clone_attributes_into!([:upc], :tracks_attributes)
      hash.should == { :upc => "1234" }
    end
    
    it "does not change anything when album does not have selected attributes" do
      hash = XmlMapper::XmlMapperHash.new.merge(:upc => "12343", :tracks_attributes => [:track_number => 1])
      hash.clone_attributes_into!([:artist_name], :tracks_attributes)
      hash.should == { 
        :upc => "12343", :tracks_attributes => [:track_number => 1] 
      }
    end
    
    it "clones all selected attributes" do
      hash = XmlMapper::XmlMapperHash.new.merge(:artist_name => "Mos Def", :title => "Some Title", :upc => "12343",
        :tracks_attributes => [{ :track_number => 1 }, { :track_number => 2 }]
      )
      hash.clone_attributes_into!([:artist_name, :upc], :tracks_attributes)
      hash.should == { 
        :artist_name => "Mos Def", :title => "Some Title", :upc => "12343", 
        :tracks_attributes => [
          { :track_number => 1, :artist_name => "Mos Def", :upc => "12343" }, 
          { :track_number => 2, :artist_name => "Mos Def", :upc => "12343" }
        ]
      }
    end
    
    it "allows cloning of attributes into multiple arrays" do
      hash = XmlMapper::XmlMapperHash.new.merge(:upc => "12343",
        :tracks_attributes => [{ :track_number => 1 }, { :track_number => 2 }],
        :videos_attributes => [{ :video_number => 1 }, { :video_number => 2 }]
      )
      hash.clone_attributes_into!(:upc, [:tracks_attributes, :videos_attributes])
      hash.should == {
        :upc => "12343",
        :tracks_attributes => [{ :track_number => 1, :upc => "12343" }, { :track_number => 2, :upc => "12343" }],
        :videos_attributes => [{ :video_number => 1, :upc => "12343" }, { :video_number => 2, :upc => "12343" }]
      }
    end
    
    it "does not overwrite already set attributes" do
      hash = XmlMapper::XmlMapperHash.new.merge(:artist_name => "Mos Def", :title => "Some Title", :upc => "12343", 
        :tracks_attributes => [
          { :track_number => 1 }, { :track_number => 2, :artist_name => "Mos and Talib" }
        ]
      )
      hash.clone_attributes_into!([:artist_name, :upc], :tracks_attributes)
      hash.should == { :artist_name => "Mos Def", :title => "Some Title", :upc => "12343", :tracks_attributes => [
          { :track_number => 1, :artist_name => "Mos Def", :upc => "12343" }, { :track_number => 2, :artist_name => "Mos and Talib", :upc => "12343" }
        ]
      }
    end
  end
  
  describe "#strip_attributes!" do
    it "strips strings in simple hashes" do
      hash = XmlMapper::XmlMapperHash.new.merge(:artist_name => " Test ")
      hash.strip_attributes!(hash)
      hash.should == { :artist_name => "Test" }
    end
    
    it "sets blank attributes to nil" do
      hash = XmlMapper::XmlMapperHash.new.merge(:artist_name => "  ")
      hash.strip_attributes!(hash)
      hash.should == { :artist_name => nil }
    end

    it "does not change nil values" do
      hash = XmlMapper::XmlMapperHash.new.merge(:artist_name => nil)
      hash.strip_attributes!(hash)
      hash.should == { :artist_name => nil }
    end

    it "does strip nested hashes" do
      hash = XmlMapper::XmlMapperHash.new.merge(:meta => { :title => " title " })
      hash.strip_attributes!(hash)
      hash.should == { :meta => { :title => "title" } }
    end

    it "does strip values in nested arrays" do
      hash = XmlMapper::XmlMapperHash.new.merge(:tracks => [ { :title => " title 1 " }, { :title => " title 2 " } ])
      hash.strip_attributes!(hash)
      hash.should == { :tracks => [ { :title => "title 1" }, { :title => "title 2" } ] }
    end
  end
end
