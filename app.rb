require 'digest/sha1'
require 'blitline'
require 'dalli'
require 'sinatra'

set :cache, Dalli::Client.new(ENV['MEMCACHE_SERVERS'],
  :username => ENV['MEMCACHE_USERNAME'],
  :password => ENV['MEMCACHE_PASSWORD'],
  )

get '/' do
  blitline(params[:url])
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
