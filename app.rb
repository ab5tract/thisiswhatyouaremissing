require 'sinatra'
require 'youtube_it'
require './youtube_it_fix'

configure :development do
  require './devenv'
end

helpers do
  def client
    @client ||= YouTubeIt::Client.new(
      :username => ENV['YOUTUBE_USERNAME'],
      :password => ENV['YOUTUBE_PASSWORD'],
      :dev_key  => ENV['YOUTUBE_DEV_KEY'],
      :debug    => true
    )
  end

  def fields_param(atts)
    atts.empty? ? {} : { :fields => { :entry => atts.join(',') } }
  end

  def query(atts)
    {}.merge(fields_param(atts))
  end

  def attribute_mapping
    {
      :title        => 'title',
      :published_at => 'published',
      :view_count   => 'yt:statistics(@viewCount)',
      :state        => 'app:control(yt:state)',
      :player_url   => 'media:group(media:player(@url))'
    }
  end

  def generate_attributes(att_map)
    client_atts = []
    server_atts = []

    att_map.each do |k,v|
      client_atts << k
      server_atts << v
    end

    {
      :client => client_atts,
      :server => server_atts
    }
  end

  def project_feed(atts = [])
    client.videos_by(query(atts)).videos
  end

  def video_to_hash(atts, video)
    atts.reduce({}) { |hash, att| hash[att] = video.send(att); hash }
  end
end

before do
  @attributes = generate_attributes(attribute_mapping)
end

get '/videos/:projected' do
  if params[:projected] == 'true'
    videos = project_feed(@attributes[:server])
  else
    videos = project_feed()
  end
  
  videos = videos.map { |video| video_to_hash(@attributes[:client], video) }

  idx = Dir.entries('./results').map { |name| (name.match(/(\d+)/) || [0])[0].to_i }.sort.last + 1

  f = File.new("./results/results#{idx}", 'w+')

  videos.each { |video| video.each { |k,v| f.write "#{k}: #{v}\n" } }
  f.close
end

get '/experiment' do
  total = 0

  loop do
    videos = project_feed
    total += videos.size

    video = videos.find { |v| v.state.include? 'requesterRegion' }

    break if total >= 1000 !video.nil?
  end

  puts "total: #{total}"

  f = File.new("./results/hits", 'a+')
  video_to_hash(@attributes[:client], video).each { |k,v| f.write "#{k}: #{v}\n" }
  f.close
end