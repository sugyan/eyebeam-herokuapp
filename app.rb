require 'digest/sha1'
require 'dalli'
require 'face'
require 'haml'
require 'json'
require 'omniauth-twitter'
require 'sinatra'
require 'stringio'
require 'tempfile'
require 'RMagick'

use OmniAuth::Builder do
  provider :twitter, ENV['TWITTER_CONSUMER_KEY'], ENV['TWITTER_CONSUMER_SECRET']
end

enable :logging
enable :sessions

set :cache, Dalli::Client.new(ENV['MEMCACHE_SERVERS'],
  :username => ENV['MEMCACHE_USERNAME'],
  :password => ENV['MEMCACHE_PASSWORD'],
  )
set :haml, :format      => :html5
set :haml, :escape_html => true

get '/' do
  haml :index
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
    draw_beam(img, tags)
    settings.cache.set("beam:#{ sha1 }", img.to_blob{ self.format = 'JPG' })
    redirect "/result/#{ sha1 }"
  else
    logger.info 'no faces'
    redirect '/failed'
  end
end

def draw_beam (img, tags)
  d = Magick::Draw.new
  tags.reverse.each do |tag|
    return unless tag['eye_left'] && tag['eye_right']
    logger.info tag
    reye = [tag['eye_right']['x'] * img.columns / 100.0, tag['eye_right']['y'] * img.rows / 100.0]
    leye = [tag['eye_left']['x']  * img.columns / 100.0, tag['eye_left']['y']  * img.rows / 100.0]
    line = Proc.new{ |eye, angle, pitch|
      edge = Proc.new{ |s|
        if s >= 0
          [0, eye[1] - (pitch >= 0 ? 1 : -1) * s * eye[0]]
        else
          [img.columns, eye[1] + (pitch >= 0 ? 1 : -1) * s * (img.columns - eye[0])]
        end
      }
      slope0 = Math::tan((90 - angle + 3) / 180 * Math::PI)
      slope1 = Math::tan((90 - angle - 3) / 180 * Math::PI)
      edge0 = edge.call(slope0)
      edge1 = edge.call(slope1)
      d.polygon(eye[0], eye[1], edge0[0], edge0[1], edge1[0], edge1[1])
    }
    cangle = tag['roll'] + (tag['pitch'] > 0 ? 1 : -1) * tag['yaw']
    langle = cangle + 30 * (1 - tag['pitch'].abs / 90.0) * (1 - tag['yaw'].abs / 90.0)
    rangle = cangle - 30 * (1 - tag['pitch'].abs / 90.0) * (1 - tag['yaw'].abs / 90.0)
    d.stroke(['red', 'green', 'yellow', 'pink', 'purple'][rand 5])
    d.stroke_width(5)
    d.stroke_opacity(0.3)
    d.fill('white')
    d.fill_opacity(0.7)
    line.call(leye, langle, tag['pitch'])
    line.call(reye, rangle, tag['pitch'])
    d.draw(img)
  end
end
