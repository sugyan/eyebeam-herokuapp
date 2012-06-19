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
include Math

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
      unless 0.upto(5).map{ |i| settings.cache.get("recent#{i}") }.include?(sha1)
        5.downto(1).each do |i|
          settings.cache.set("recent#{ i }", settings.cache.get("recent#{ i - 1 }"))
        end
        settings.cache.set("recent0", sha1)
      end
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
    logger.info :left => tag['eye_left'], :right => tag['eye_right']

    d = Magick::Draw.new
    reye = [tag['eye_right']['x'] * img.columns / 100.0, tag['eye_right']['y'] * img.rows / 100.0]
    leye = [tag['eye_left']['x']  * img.columns / 100.0, tag['eye_left']['y']  * img.rows / 100.0]
    color = [
      ['#FF0000', '#FF4040', '#FF8080', '#FFC0C0', '#FFFFFF'],
      ['#00FF00', '#40FF40', '#80FF80', '#C0FFC0', '#FFFFFF'],
      ['#FFFF00', '#FFFF40', '#FFFF80', '#FFFFC0', '#FFFFFF'],
      ['#FF00FF', '#FF40FF', '#FF80FF', '#FFC0FF', '#FFFFFF'],
      ['#800080', '#A040A0', '#C080C0', '#E0C0E0', '#FFFFFF'],
    ][rand 5]
    polygon = Proc.new{ |eye, angle, openness|
      logger.info "angle: #{ angle }"
      edge = Proc.new{ |a|
        s = Math::tan(a / 180 * Math::PI)
        if a.abs >= 90
          [0,           eye[1] + s * eye[0]]
        else
          [img.columns, eye[1] - s * (img.columns - eye[0])]
        end
      }
      # draw
      d.stroke_width(0)
      d.stroke_opacity(0)
      0.upto(4).each do |i|
        edge0 = edge.call(angle + (10 - i * 1.5) * openness)
        edge1 = edge.call(angle - (10 - i * 1.5) * openness)
        d.fill(color[i])
        d.fill_opacity(0.1 + i * 0.08)
        d.polygon(eye[0], eye[1], edge0[0], edge0[1], edge1[0], edge1[1])
      end
    }
    width = 1 + (tag['width'] + tag['height']) / 20.0
    d.stroke(color[0])
    # light source
    d.stroke_width(width - 1)
    d.stroke_opacity(0.1)
    d.fill('white')
    d.fill_opacity(0.2)
    d.ellipse(leye[0], leye[1], width, width, 0, 360)
    d.ellipse(reye[0], reye[1], width, width, 0, 360)
    # beam
    p = tag['pitch'] * PI / 180
    r = tag['roll']  * PI / 180
    y = tag['yaw']   * PI / 180
    logger.info "roll : #{ tag['roll']  } (#{ r })"
    logger.info "pitch: #{ tag['pitch'] } (#{ p })"
    logger.info "yaw  : #{ tag['yaw']   } (#{ y })"
    c = (p >= 0 ? 90 : -90) + (atan2(sin(p), sin(y / 2)) / PI * 180 + (p >= 0 ? -90 : 90)) / 2
    cangle = c - tag['roll']
    openness = (1 - sin(p.abs)) ** 3 * (1 - sin(y.abs)) ** 3
    logger.info "cangle: #{ cangle }"
    logger.info "open  : #{ openness }"
    langle = cangle + (p >= 0 ? 1 : -1) * 60 * openness
    rangle = cangle - (p >= 0 ? 1 : -1) * 60 * openness
    polygon.call(leye, langle, openness)
    polygon.call(reye, rangle, openness)
    d.draw(img)
  end
  return success
end
