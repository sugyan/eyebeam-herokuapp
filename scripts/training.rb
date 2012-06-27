#!/usr/bin/env ruby
require 'face'
require 'logger'

log = Logger.new(STDOUT)
client = Face.get_client(:api_key => ENV['FACECOM_API_KEY'], :api_secret => ENV['FACECOM_API_SECRET'])

members = ['momota', 'ariyasu', 'tamai', 'sasaki', 'takagi']
### tag.save
# members.each do |member|
#   detect = client.faces_detect(:urls => "http://www.momoclo.net/member/#{ member }/img/profile.jpg")
#   tid    = detect['photos'][0]['tags'][0]['tid']
#   log.info "save: #{ tid }"
#   result = client.tags_save(:tids => tid, :uid => "#{ member }@sugi1982")
#   log.info result
# end
# log.info client.faces_status(:uids => members.map{ |m| "#{m}@sugi1982" }.join(','))
