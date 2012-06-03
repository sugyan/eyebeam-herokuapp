require 'digest/sha1'
require 'blitline'
require 'dalli'
require 'haml'
require 'json'
require 'open-uri'
require 'rexml/document'
require 'sinatra'

enable :logging

set :cache, Dalli::Client.new(ENV['MEMCACHE_SERVERS'],
  :username => ENV['MEMCACHE_USERNAME'],
  :password => ENV['MEMCACHE_PASSWORD'],
  )
set :haml, :format      => :html5
set :haml, :escape_html => true

get '/' do
  haml :index
end

get '/image' do
  if url = params[:url]
    json = blitline(url)
    haml :image, :locals => { :s3_url => json['results'][0]['images'][0]['s3_url'] }
  else
    error 400, 'Bad Request'
  end
end

get '/api/face' do
  if url = params[:url]
    data = kaolabo(url)
    data
  else
    error 400, 'Bad Request'
  end
end

def blitline (url)
  key = 'blitline:' + Digest::SHA1.hexdigest(url)
  if cached = settings.cache.get(key)
    return cached
  else
    job = Blitline::Job.new(url)
    job.application_id = ENV['BLITLINE_APPLICATION_ID']
    function = job.add_function('resize_to_fit', { :width  => 384, :height => 384 })
    function.add_save('eyebeam')
    blitline = Blitline.new
    blitline.jobs << job
    json = blitline.post_jobs
    logger.info json
    settings.cache.set(key, json)
    return json
  end
end

def kaolabo (url)
  key = 'kaolabo:' + Digest::SHA1.hexdigest(url)
  if cached = settings.cache.get(key)
    return cached
  else
    uri = "https://kaolabo.com/api/detect?apikey=#{ ENV['KAOLABO_APIKEY'] }&url=#{ URI.encode(url) }"
    doc = REXML::Document.new(open(uri).read)
    face = doc.elements['results/faces[1]/face']
    data = {
      :face => {
        :height => face.attributes['height'],
        :width  => face.attributes['width'],
        :x      => face.attributes['x'],
        :y      => face.attributes['y'],
      },
      :left_eye => {
        :x => face.elements['left-eye'].attributes['x'],
        :y => face.elements['left-eye'].attributes['y'],
      },
      :right_eye => {
        :x => face.elements['right-eye'].attributes['x'],
        :y => face.elements['right-eye'].attributes['y'],
      }
    }.to_json
    logger.info data
    settings.cache.set(key, data)
    return data
  end
end
