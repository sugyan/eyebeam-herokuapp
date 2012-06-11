require 'face'
require 'json'
require 'RMagick'

file = 'profile.jpg'
face = Face.get_client(:api_key => ENV['FACECOM_API_KEY'], :api_secret => ENV['FACECOM_API_SECRET'])
json = face.faces_detect(:file => File.new(file, 'rb'))

p json['usage']['remaining']
json['photos'][0]['tags'].each do |tag|
  return unless tag['eye_left'] && tag['eye_right']
  puts JSON.pretty_generate(tag)
  img = Magick::ImageList.new(file)
  d = Magick::Draw.new
  d.stroke('blue')
  angle = tag['roll'] + (tag['pitch'] > 0 ? 1 : -1) * tag['yaw']
  reye = [tag['eye_right']['x'] * img.columns / 100.0, tag['eye_right']['y'] * img.rows / 100.0]
  leye = [tag['eye_left']['x']  * img.columns / 100.0, tag['eye_left']['y']  * img.rows / 100.0]
  line = Proc.new { |eye, angle, pitch|
    slope = Math::tan((90 - angle) / 180 * Math::PI)
    puts slope
    if pitch >= 0
      if slope >= 0
        d.line(eye[0], eye[1], 0, eye[1] - slope * eye[0])
      else
        d.line(eye[0], eye[1], img.columns, eye[1] + slope * (img.columns - eye[0]))
      end
    else
      if slope >= 0
        d.line(eye[0], eye[1], 0, eye[1] + slope * eye[0])
      else
        d.line(eye[0], eye[1], img.columns, eye[1] - slope * (img.columns - eye[0]))
      end
    end
  }
  line.call(leye, angle + 30 * (1 - tag['pitch'].abs / 90.0) * (1 - tag['yaw'].abs / 90.0), tag['pitch'])
  line.call(reye, angle - 30 * (1 - tag['pitch'].abs / 90.0) * (1 - tag['yaw'].abs / 90.0), tag['pitch'])
  d.draw(img)
  img.write('out.jpg')
end
