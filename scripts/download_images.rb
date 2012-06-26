#!/usr/bin/env ruby
require 'logger'
require 'nokogiri'
require 'open-uri'

log = Logger.new(STDOUT)
# target year/month
today = Date.today
array = []
today.month.downto(1).each do |m|
  array.push('%04d%02d' % [today.year, m])
end
(today.year - 1).downto(2011).each do |y|
  12.downto(1).each do |m|
    array.push('%04d%02d' % [y, m])
  end
end

['momota', 'ariyasu', 'tamai', 'sasaki', 'takagi'].each do |member|
  # base directory
  basedir = File.absolute_path(File.dirname(__FILE__) + "/../data/#{ member }")
  File.directory?(basedir) or Dir.mkdir(basedir)
  array.each do |dir|
    # target directory
    dirname = File.absolute_path("#{ basedir }/#{ dir }")
    File.directory?(dirname) or Dir.mkdir(dirname)
    # fetch imagelist
    url = "http://ameblo.jp/#{ member }-sd/imagelist-#{ dir }.html"
    # download all images
    while true do
      log.info("fetch #{ url } ...")
      doc = Nokogiri::HTML(open(url))
      doc.css('#imageList li').each do |li|
        # original size
        img = li.css('img')[0]['src'].sub('imgstat.ameba.jp/view/d/90/stat001.ameba.jp', 'stat.ameba.jp')
        log.info("download #{ img }")
        # save
        file = img.sub(/^.*\//, '')
        File.open("#{ dirname }/#{ file }", 'wb') { |f|
          f.write(open(img).read)
        }
        # wait!
        sleep 1
      end
      # nextpage?
      if fwd = doc.css('a.fwd')[0]
        url = fwd['href']
      else
        break
      end
    end
  end
end
