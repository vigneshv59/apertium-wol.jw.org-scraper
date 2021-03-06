require 'open-uri'
require 'optparse'
require 'nokogiri'
require 'uri'
require 'date'
require 'rest-client'

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

options[:add] = false

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: scraper.rb [options] lang1 lang2"
  
  opts.on("-oOUTPUT", "--out=OUTPUT", "The out file name. (Mandatory)") do |o|
    options[:out] = o
  end
  
  opts.on("--date=DATE", "The date range, format YYYY-MM-DD:YYYY-MM-DD. (Mandatory)") do |dr|
    m = /(.*):(.*)/.match(dr)
    e = m[2]
    s = m[1]
    options[:end] = Date.strptime(e, '%Y-%m-%d')
    options[:start] = Date.strptime(s, '%Y-%m-%d')
    if options[:end].nil?
      options[:end] = Date.today
    end
    
    if options[:start].nil?
      options[:start] = Date.today
    end
  end
  
  opts.on("-a", "--add", "Set this flag if you want to add to an existing file (passed as OUTPUT)") do |a|
    options[:add] = a
  end
end

options[:l1] = ARGV[-2]
options[:l2] = ARGV[-1]
begin
  optparse.parse!
  if options[:l1].nil? || options[:l2].nil? || options[:out].nil?
    raise OptionParser::MissingArgument
  end
rescue OptionParser::MissingArgument, OptionParser::InvalidOption
  puts optparse
  exit
end

base_lang_page1 = Nokogiri::HTML(RestClient.get("http://wol.jw.org/#{options[:l1]}"), nil, 'UTF-8')
base_lang_page2 = Nokogiri::HTML(RestClient.get("http://wol.jw.org/#{options[:l2]}"), nil, 'UTF-8')

path1 = base_lang_page1.at_css(".todayNav")["href"]
path2 = base_lang_page2.at_css(".todayNav")["href"]

path1 = path1 << "/#{options[:start].year}/#{options[:start].month}/#{options[:start].day}"
path2 = path2 << "/#{options[:start].year}/#{options[:start].month}/#{options[:start].day}"

uri1 = URI(File.join("http://wol.jw.org", path1))
uri2 = URI(File.join("http://wol.jw.org", path2))

date = options[:start]
to_date = options[:end]
current_week = -1

if date >= to_date
  puts "The end date must be later than the start date!"
  exit
end

urls = []
weeks = []

if options[:add]
  add_file = Nokogiri::XML(open(options[:out]), nil, "UTF-8")
  if add_file.nil?
    puts "File #{options[:out]} does not exist or is not valid XML."
    exit
  end
  
  notes = add_file.xpath("//note")
  notes.each do |n|
    r = /(.*)=(.*), (.*)=(.*)/.match(n.text)
    url = r[2]
    urls << r[2]
    urls << r[4]
    
    r2 = /Week ([\d]*)/.match(n.text)
    if !r2.nil?
      weeks << "#{r2[1]}+#{r[4].split('/')[-3]}"
    end
  end
  
  xml_doc = Nokogiri::Slop(add_file.to_xml)
end
 
while date <= to_date
  uri1.path = uri1.path.split('/')[0...-3].join("/") << "/#{date.year}/#{date.month}/#{date.day}"
  uri2.path = uri2.path.split('/')[0...-3].join("/") << "/#{date.year}/#{date.month}/#{date.day}"
  
  if options[:add]
    if urls.include?(uri1.to_s) || urls.include?(uri2.to_s)
      puts("#{date} skipped (was already in file)")
      date = date + 1
      next
    end
  end
  
  page1 = Nokogiri::HTML(open(uri1.to_s).read, nil, 'UTF-8')
  page2 = Nokogiri::HTML(open(uri2.to_s).read, nil, 'UTF-8')
  
  add_week = true
  if options[:add] && weeks.include?("#{date.strftime("%U").to_i}+#{date.year}") && current_week != date.strftime("%U").to_i
    puts("Week #{date.strftime("%U").to_i}+#{date.year} skipped (was already in file).")
    add_week = false
    current_week = date.strftime("%U").to_i
  end
  
  
  if !page1.xpath('//*[@class="bodyTxt"]').xpath('.//text()').text.strip.empty?
    xml_doc.tmx.body.add_child("<tu> <note>#{options[:l1]}=#{uri1.to_s}, #{options[:l2]}=#{uri2.to_s}</note><tuv xml:lang=\"#{options[:l1]}\"><seg>#{page1.xpath('//*[@class="bodyTxt"]').xpath('.//text()').text.strip}</seg></tuv><tuv xml:lang=\"#{options[:l2]}\"><seg>#{page2.xpath('//*[@class="bodyTxt"]').xpath('.//text()').text.strip}</seg></tuv></tu>")
  end
  
  if current_week != date.strftime("%U").to_i && !page1.xpath('//*[@class="groupMtgSched"]').xpath('.//text()').text.strip.empty? && add_week
    xml_doc.tmx.body.add_child("<tu> <note>(Week #{date.strftime("%U").to_i}) #{options[:l1]}=#{uri1.to_s}, #{options[:l2]}=#{uri2.to_s}</note><tuv xml:lang=\"#{options[:l1]}\"><seg>#{page1.xpath('//*[@class="groupMtgSched"]').xpath('.//text()').text.strip}</seg></tuv><tuv xml:lang=\"#{options[:l2]}\"><seg>#{page2.xpath('//*[@class="groupMtgSched"]').xpath('.//text()').text.strip}</seg></tuv></tu>")
    current_week = date.strftime("%U").to_i
  end
  
  puts(date)
  date = date + 1
end

write_xml(xml_doc, options)