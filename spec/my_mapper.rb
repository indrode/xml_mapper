require "xml_mapper"
require "date"

class MyMapper < XmlMapper
  text :title, :version_title                         # 1:1 - maps xpaths title and version_title to attribute keys
  integer :released_in                                # converts value to an integer
  text :country, :after_map => :upcase                # calls after_map method on extracted value if value responds to the method
  text :released_on, :after_map => :parse_date        # calls after_map method defined in Mapper class when value does not respond
  boolean :allows_streaming                           # maps Y, y, yes, true => true, N, n, no, false => false
  
  within :artist do
    text :name => :artist_name                        # adds mapping for xpath "artist/name"
    integer :id => :artist_id
  end
  
  many "tracks/track" => :tracks do                   # maps xpath "tracks/track" to array with key :tracks
    text :title => :track_title
    integer :number => :track_number
    integer :disk => :disk_number
    exists :explicit_lyrics                           # checks if a node with the xpath exists
  end
  
  after_map do                                        # is called after attributes are extracted, self references the extracted attributes
    self[:tracks_count] = self[:tracks].length
  end
  
  # to be used for after_map callbacks
  def parse_date(date_string)
    Date.parse(date_string)
  end
end