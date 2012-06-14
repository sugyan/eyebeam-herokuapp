require 'digest/sha1'
require 'dalli'
require 'face'
require 'haml'
require 'json'
require 'omniauth-twitter'
require 'omniauth-facebook'
require 'sinatra'
require 'tempfile'
require 'RMagick'

use OmniAuth::Builder do
  provider :twitter,  ENV['TWITTER_CONSUMER_KEY'], ENV['TWITTER_CONSUMER_SECRET']
  provider :facebook, ENV['FACEBOOK_APP_ID'],      ENV['FACEBOOK_APP_SECRET']
end

enable :logging
enable :sessions

set :cache, Dalli::Client.new(ENV['MEMCACHE_SERVERS'],
  :username => ENV['MEMCACHE_USERNAME'],
  :password => ENV['MEMCACHE_PASSWORD'],
  )
set :haml, :format      => :html5
set :haml, :escape_html => true

error 400 do
  haml :error, :locals => { :code => 400, :message => 'Bad Request' }
end

error 404 do
  haml :error, :locals => { :code => 404, :message => 'Not Found' }
end

get '/' do
  recents = 0.upto(5).map do |i|
    if sha1 = settings.cache.get("recent#{ i }")
      sha1 if settings.cache.get("beam:#{ sha1 }")
    end
  end
  haml :index, :locals => { :recents => recents }
end

get '/failed' do
  haml :failed
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

get '/auth/twitter/callback' do
  auth = request.env['omniauth.auth']
  logger.info auth.info
  begin
    submit(auth.info.image)
  rescue => e
    logger.warn e.message
    error 400, 'Bad Request'
  end
end

get '/auth/facebook/callback' do
  auth = request.env['omniauth.auth']
  logger.info auth.info
  begin
    submit(auth.info.image.gsub(/square/, 'large'))
  rescue => e
    logger.warn e.message
    error 400, 'Bad Request'
  end
end

post '/url' do
  begin
    raise 'no url' if params[:url].length < 1
    submit(params[:url])
  rescue => e
    logger.warn e.message
    error 400, 'Bad Request'
  end
end

post '/upload' do
  begin
    raise 'no file' unless params[:image]
    submit(params[:image][:tempfile].path)
  rescue => e
    logger.warn e.message
    error 400, 'Bad Request'
  end
end

def submit (path)
  img  = Magick::ImageList.new(path).resize_to_fit(460)
  blob = img.to_blob{ self.format = 'JPG' }
  sha1 = Digest::SHA1.hexdigest(blob)
  if json = settings.cache.get("face:#{ sha1 }")
    data = JSON.parse(json)
  else
    face = Face.get_client(:api_key => ENV['FACECOM_API_KEY'], :api_secret => ENV['FACECOM_API_SECRET'])
    file = Tempfile.new(sha1)
    file.write(blob)
    data = face.faces_detect(:file => File.new(file.path, 'rb'))
    settings.cache.set("face:#{ sha1 }", data.to_json)
  end
  logger.info data['usage']['remaining']
  tags = data['photos'][0]['tags']
  if tags.length > 0
    settings.cache.set("orig:#{ sha1 }", blob)
    if draw_beam(img, tags)
      settings.cache.set("beam:#{ sha1 }", img.to_blob{ self.format = 'JPG' })
      5.downto(1).each do |i|
        settings.cache.set("recent#{ i }", settings.cache.get("recent#{ i - 1 }"))
      end
      settings.cache.set("recent0", sha1)
      redirect "/result/#{ sha1 }"
    end
  end
  logger.info 'no faces'
  redirect '/failed'
end

def draw_beam (img, tags)
  success = false
  tags.reverse.each do |tag|
    next unless tag['eye_left'] && tag['eye_right']
    success = true
    logger.info tag
    d = Magick::Draw.new
    reye = [tag['eye_right']['x'] * img.columns / 100.0, tag['eye_right']['y'] * img.rows / 100.0]
    leye = [tag['eye_left']['x']  * img.columns / 100.0, tag['eye_left']['y']  * img.rows / 100.0]
    polygon = Proc.new{ |eye, angle, updown|
      puts "angle: #{ angle }"
      puts "roll: #{ tag['roll'] }"
      edge = Proc.new{ |a|
        s = updown * Math::tan(a / 180 * Math::PI)
        puts "s: #{ s }, a: #{ a }"
        if a.abs - 90 >= 0
          [0,           eye[1] - s * eye[0]]
        else
          [img.columns, eye[1] + s * (img.columns - eye[0])]
        end
      }
      edge0 = edge.call(angle + 2.5)
      edge1 = edge.call(angle - 2.5)
      d.polygon(eye[0], eye[1], edge0[0], edge0[1], edge1[0], edge1[1])
    }
    width = 1 + (tag['width'] + tag['height']) / 20.0
    # color
    d.stroke(['#FF0000', '#00FF00', '#FFFF00', '#FF00FF', '#800080'][rand 5])
    # light source
    d.stroke_width(width - 1)
    d.stroke_opacity(0.1)
    d.fill('white')
    d.fill_opacity(0.2)
    d.ellipse(leye[0], leye[1], width, width, 0, 360)
    d.ellipse(reye[0], reye[1], width, width, 0, 360)
    # beam
    d.stroke_width(width + 2)
    d.stroke_opacity(0.4)
    d.fill_opacity(0.6)

    # FIXME
    updown = tag['pitch'] > 0 ? 1 : -1
    cangle = updown * 90 - tag['roll'] + tag['yaw']
    puts "cangle: #{ cangle }"
    langle = cangle - 30 * (1 - tag['pitch'].abs / 90.0) * (1 - tag['yaw'].abs / 90.0)
    rangle = cangle + 30 * (1 - tag['pitch'].abs / 90.0) * (1 - tag['yaw'].abs / 90.0)
    polygon.call(leye, langle, updown)
    polygon.call(reye, rangle, updown)
    d.draw(img)
  end
  return success
end
