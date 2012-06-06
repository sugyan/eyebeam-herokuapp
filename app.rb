require 'digest/sha1'
require 'blitline'
require 'dalli'
require 'haml'
require 'net/https'
require 'json'
require 'rexml/document'
require 'RMagick'
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

get '/result/:sha1' do
  sha1 = params[:sha1]
  if settings.cache.get("orig:#{ sha1 }") && settings.cache.get("beam:#{ sha1 }")
    haml :result
  else
    error 404, 'Not Found'
  end
end

get '/:kind/:path' do
  kind = params[:kind].match(/^(orig|beam)$/)
  sha1 = params[:path].match(/(\w+).jpg/)
  if kind && sha1 && (data = settings.cache.get("#{ kind }:#{ sha1[1] }"))
    content_type 'image/jpeg'
    data
  else
    error 404, 'Not Found'
  end
end

post '/submit' do
  begin
    img  = Magick::ImageList.new(params[:url] || params[:image][:tempfile].path).resize_to_fit(460)
    data = img.to_blob{ self.format = 'JPG' }
    sha1 = Digest::SHA1.hexdigest(data)
    face = kaolabo_post(data, sha1)
    if face
      settings.cache.set("orig:#{ sha1 }", data)
      draw_beam(img, face)
      settings.cache.set("beam:#{ sha1 }", img.to_blob)
      redirect "/result/#{ sha1 }"
    else
      logger.info 'no faces'
      haml :failed
    end
  rescue => e
    logger.warn e
    error 400, 'Bad Request'
  end
end

def kaolabo_post (data, sha1)
  key = "kaolabo:data:#{ sha1 }"
  if cached = settings.cache.get(key)
    return JSON.parse(cached)
  else
    https = Net::HTTP.new('kaolabo.com', 443)
    https.use_ssl = true
    res = https.post("/api/detect?apikey=#{ ENV['KAOLABO_APIKEY'] }", data, { 'Content-Type' => 'image/jpeg' })
    doc = REXML::Document.new(res.body)
    face = doc.elements['results/faces[1]/face']
    return unless face
    data = {
      'face' => {
        'h' => face.attributes['height'].to_i,
        'w' => face.attributes['width'].to_i,
        'x' => face.attributes['x'].to_i,
        'y' => face.attributes['y'].to_i,
      },
      'leye' => {
        'x' => face.elements['left-eye'].attributes['x'].to_i,
        'y' => face.elements['left-eye'].attributes['y'].to_i,
      },
      'reye' => {
        'x' => face.elements['right-eye'].attributes['x'].to_i,
        'y' => face.elements['right-eye'].attributes['y'].to_i,
      }
    }
    logger.info data
    settings.cache.set(key, data.to_json)
    return data
  end
end

def draw_beam (img, face)
  c = [
    (face['leye']['x'] + face['reye']['x']) / 2.0,
    (face['leye']['y'] + face['reye']['y']) / 2.0,
  ]
  f = [
    face['face']['x'] + face['face']['w'] / 2.0,
    face['face']['y'] + face['face']['h'] / 2.0,
  ]
  slope = (c[0] == f[0]) ? (rand - 0.5) * 10 : (c[1] - f[1]) / (c[0] - f[0])

  d = Magick::Draw.new
  d.stroke_linecap('round')
  draw_line = Proc.new { |color, width, opacity|
    d.stroke(color)
    d.stroke_width(width)
    d.stroke_opacity(opacity)
    if slope >= 0
      d.line(face['leye']['x'], face['leye']['y'], 0, face['leye']['y'] - slope * 1.1 * face['leye']['x'])
      d.line(face['reye']['x'], face['reye']['y'], 0, face['reye']['y'] - slope / 1.1 * face['reye']['x'])
    else
      d.line(face['leye']['x'], face['leye']['y'], img.columns, face['leye']['y'].to_f + slope / 1.1 * (img.columns - face['leye']['x'].to_f))
      d.line(face['reye']['x'], face['reye']['y'], img.columns, face['reye']['y'].to_f + slope * 1.1 * (img.columns - face['reye']['x'].to_f))
    end
  }
  draw_line.call('blue',  5, 0.3)
  draw_line.call('white', 3, 0.7)
  d.draw(img)
end
