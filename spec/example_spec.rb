require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

require File.expand_path(File.dirname(__FILE__) + "/my_mapper")

describe "ExampleSpec" do
  describe "mapping spec/fixtures/base.xml" do
    before(:all) do
      @attributes = MyMapper.attributes_from_xml_path(File.expand_path(File.dirname(__FILE__) + '/fixtures/base.xml'))
    end
    
    { 
      :title => "Black on Both Sides", :version_title => "Extended Edition", :released_in => 1999,
      :artist_name => "Mos Def", :artist_id => 1212, :country => "DE", :allows_streaming => true,
      :tracks_count => 2, :released_on => Date.new(1999, 10, 12), :contributions => [ 
        { :role => "artist", :name => "Mos Def" },
        { :role => "producer", :name => "DJ Premier" },
      ]
    }.each do |key, value|
      it "extracts #{value.inspect} as #{key}" do
        @attributes[key].should == value
      end
    end
    
    [
      { :track_title => "Fear Not of Man", :track_number => 1, :disk_number => 1, :explicit_lyrics => true, :isrc => "1234" },
      { :track_title => "Hip Hop", :track_number => 2, :disk_number => 1, :explicit_lyrics => false, :isrc => "2345" },
    ].each_with_index do |hash, offset|
      hash.each do |key, value|
        it "extracts #{value.inspect} for #{key} for track with offset #{offset}" do
          @attributes[:tracks][offset][key].should == value
        end
      end
    end
  end
end