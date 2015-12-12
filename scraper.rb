require 'open-uri'
require 'optparse'
require 'nokogiri'
require 'uri'
require 'date'


def write_xml(xml, options)
  xsl =<<XSL
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">  
  <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
  <xsl:strip-space elements="*"/>
  <xsl:template match="/">
    <xsl:copy-of select="."/>
  </xsl:template>
</xsl:stylesheet>  
XSL

  xslt = Nokogiri::XSLT(xsl)
  out  = xslt.transform(xml)
  out.create_internal_subset('tmx', nil, "tmx14.dtd")
  open(options[:out] || "out.txt", "w:UTF-8") do |f|
    f.puts(out.to_xml(:indent => 5))
  end
end

b = Nokogiri::XML::Builder.new do |xml|
  xml.tmx(:version => "1.4") {
    xml.header(:creationtool => "wol.jw.org scraper", :segtype => "paragraph", :datatype => "PlainText")
    xml.body
  }
end

xml_doc = Nokogiri::Slop(b.to_xml)
options = {}

Signal.trap("INT") { 
  write_xml(xml_doc, options)
  exit
}

# Trap `Kill `
Signal.trap("TERM") {
  write_xml(xml_doc, options)
  exit
}


optparse = OptionParser.new do |opts|
  opts.banner = "Usage: scraper.rb [options]"

  opts.on("--url1=URL1", "The URL for the 1st language. (Mandatory)") do |u1|
    options[:url1] = u1
  end
  
  opts.on("--url2=URL2", "The URL for the 2nd language. (Mandatory)") do |u2|
    options[:url2] = u2
  end
  
  opts.on("--lang1=LANG1", "The language code for the 1st language. (Mandatory)") do |l1|
    options[:l1] = l1
  end
  
  opts.on("--lang2=LANG2", "The language code for the 2nd language. (Mandatory)") do |l2|
    options[:l2] = l2
  end
  
  opts.on("-oOUTPUT", "--out=OUTPUT", "The out file name. (Mandatory)") do |o|
    options[:out] = o
  end
  
  opts.on("-eEND_DATE", "--end=END_DATE", "The end date, format YYYY-MM-DD. (Mandatory)") do |e|
    options[:end] = Date.strptime(e, '%Y-%m-%d')
    if options[:end].nil?
      options[:end] = Date.today
    end
  end
end

begin
  optparse.parse!
  if options[:url1].nil? || options[:url2].nil? || options[:l1].nil? || options[:l2].nil? || options[:out].nil? || options[:end].nil?
    raise OptionParser::MissingArgument
  end
rescue OptionParser::MissingArgument, OptionParser::InvalidOption
  puts optparse
  exit
end

uri1 = URI(options[:url1])
uri2 = URI(options[:url2])

date = Date.new(URI(options[:url1]).path.split('/')[-3].to_i, URI(options[:url1]).path.split('/')[-2].to_i, URI(options[:url1]).path.split('/')[-1].to_i)
to_date = options[:end]

if date >= to_date
  puts "The end date must be later than the start date!"
  exit
end


while date < to_date
  page1 = Nokogiri::HTML(open(uri1.to_s).read, nil, 'UTF-8')
  page2 = Nokogiri::HTML(open(uri2.to_s).read, nil, 'UTF-8')
  
  date = date + 1
  puts(date)
  uri1.path = uri1.path.split('/')[0...-3].join("/") << "/#{date.year}/#{date.month}/#{date.day}"
  uri2.path = uri2.path.split('/')[0...-3].join("/") << "/#{date.year}/#{date.month}/#{date.day}"
  
  xml_doc.tmx.body.add_child("<tu><tuv xml:lang=\"#{options[:l1]}\"><seg>#{page1.xpath('//*[@class="bodyTxt"]').xpath('.//text()').text.strip}</seg></tuv><tuv xml:lang=\"#{options[:l2]}\"><seg>#{page2.xpath('//*[@class="bodyTxt"]').xpath('.//text()').text.strip}</seg></tuv></tu>")
end

write_xml(xml_doc, options)