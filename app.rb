require 'digest/sha1'
require 'blitline'
require 'dalli'
require 'sinatra'
require 'haml'

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
    blitline(url)
  else
    error 400, 'Bad Request'
  end
end

def blitline (url)
  sha1 = Digest::SHA1.hexdigest(url)
  if cached = settings.cache.get(sha1)
    return cached
  else
    job = Blitline::Job.new(url)
    job.application_id = ENV['BLITLINE_APPLICATION_ID']
    function = job.add_function('resize_to_fit', { :width  => 100, :height => 100 })
    function.add_save('eyebeam')
    blitline = Blitline.new
    blitline.jobs << job
    json = blitline.post_jobs
    settings.cache.set(sha1, json)
    return json
  end
end
