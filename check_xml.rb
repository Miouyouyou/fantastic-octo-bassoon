require 'rexml/document'

if ARGV.length < 1
  abort("check_xml /path/to/xml_document.xml")
end

REXML::Document.new(File.read(ARGV[0]))
