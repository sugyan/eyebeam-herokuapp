require 'sinatra'
require 'blitline'

get '/' do
  job = Blitline::Job.new(params[:url])
  job.application_id = ENV['BLITLINE_APPLICATION_ID']
  function = job.add_function('resize_to_fit', { :width  => 100, :height => 100 })
  function.add_save('eyebeam')
  blitline = Blitline.new
  blitline.jobs << job
  blitline.post_jobs
end
