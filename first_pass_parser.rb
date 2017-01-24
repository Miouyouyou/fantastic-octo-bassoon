require 'set'
require 'cgi'

class Parser
  class Tag
    attr_reader :name, :open, :close, :attributes, :self_closing, :raw_content

    alias :open? :open
    alias :close? :close
    alias :self_closing? :self_closing
    Attribute = Struct.new(:name, :value)

    def initialize(tag_text)

      @raw_content = tag_text

      start_tag =  1
      end_tag   = -1

      @close        = (tag_text[start_tag] == "/")
      @self_closing = (tag_text[-1]        == "/")
      @open = !(@close || @self_closing)

      start_tag += 1 if @close
      end_tag   -= 1 if @self_closing

      tag_content = tag_text[start_tag..end_tag]
    
      @name = tag_content.match(/^\s*(?<tagname>[^\s\/>]*)/)[:tagname].to_sym
	  
      # What happened with Regexp and Ruby !?        
      @attributes = {}
      tag_content.
        to_enum(:scan, /(?<attribute>[^=\s]*)="(?<value>[^"\\]*(?:\\.[^"\\]*)*)"/).
        map { 
          attrib, value = Regexp.last_match.captures
          @attributes[attrib.to_sym] = value
        }

    end

    def inspect
      close = (@close ? "/" : "")
      self_close = (@self_closing ? "/" : "")
      attributes = @attributes.map {|a,v| %Q[#{a}="#{v}"]}.join(" ")
      "<#{close} tag:#{@name} attributes: #{attributes} #{self_close}>"
    end

    def to_s
      @raw_content
    end
  end


  attr_accessor :raw_content_list
  def initialize()
    @raw_content_list = Set.new
  end

  def add_raw_tags(*tags)
    self.raw_content_list.merge(tags)
  end

  def parse_raw_text(text, tag)
    CGI.escape_html(text)
  end

  def store_raw_content(text, cursor, tag, splitted_content)
    raw_content_end = 
      (text.index("</#{tag.name}", cursor) || text.length)
    splitted_content << 
      parse_raw_text(text[cursor...raw_content_end], tag)
    raw_content_end
  end

  def parse_simple_text(text)
    CGI.escape_html(text.gsub(/\s+/, " ").gsub(/^\s+$/, ""))
  end

  def store_simple_text(text, splitted_content)
    parsed_text = parse_simple_text(text)
    splitted_content << parsed_text unless parsed_text.empty?
  end

  def first_pass(text)
    splitted_content = []
    text_cursor = 0
    cursor = 0

    while (cursor = text.index(/<\S/, cursor))
      store_simple_text(text[text_cursor...cursor], splitted_content)
      markup_begin_pos = cursor
      markup_end_pos   = text.index(/[^\\]>/, cursor) + 1
      markup = text[markup_begin_pos..markup_end_pos]
		
      tag = Tag.new(markup)
      splitted_content << tag

      cursor = markup_end_pos + 1
      text_cursor = cursor

      if (raw_content_list.include?(tag.name) && tag.open?)
        cursor = 
          store_raw_content(text, cursor, tag, splitted_content)
        text_cursor = cursor
      end
		
    end # while
    splitted_content
  end # self.parse_text

  def xml(text)
    first_pass(text)
  end
end

require 'pp'
text = File.read("InvocationJNI.xml")
pouf = Parser.new
pouf.add_raw_tags(:programlisting, :code, :output)
puts pouf.xml(text).join("")

