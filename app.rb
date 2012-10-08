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

  def projecting?
    false
  end

  def fields_param
    projecting? ? { :fields => { :entry => fields_attributes[:server].join(',') } } : {}
  end

  def query_params(params = {})
    {
      :safe_search => 'none',
      :restriction => 'AF',
      :per_page    => 50,
      :page        => 1,
    }.merge(params).merge(fields_param)
  end

  def fields_attribute_mapping
    {
      :title        => 'title',
      :published_at => 'published',
      :view_count   => 'yt:statistics(@viewCount)',
      :state        => 'app:control(yt:state)',
      :player_url   => 'media:group(media:player(@url))'
    }
  end

  def generate_fields_attributes(att_map)
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

  def get_feed(params)
    client.videos_by(query_params(params)).videos
  end

  def video_to_hash(atts, video)
    atts.reduce({}) do |hash, att|
      val = video.send(att)

      puts "state val: #{val}, #{val.class}" if att == :state

      hash[att] = val
      hash
    end
  end

  def fields_attributes
    @fields_attributes ||= generate_fields_attributes(fields_attribute_mapping)
  end
end

get '/video' do
  video = get_feed({ :per_page => 1, :query => 'innocence of muslims' })[0]

  video.public_methods(false).each { |meth| puts "#{meth}: #{video.send(meth)}" }
end

get '/videos' do
  idx = Dir.entries('./results').map { |name| (name.match(/(\d+)/) || [0])[0].to_i }.sort.last + 1

  videos = get_feed({ :query => 'innocence of muslims', :page => 1 }).map { |video| video_to_hash(fields_attributes[:client], video) }

  file = File.new("./results/results#{idx}", 'w+')
  videos.each { |video| video.each { |k,v| file.write "#{k}: #{v}\n" } }
  file.close
end

get '/experiment' do
  total = 0
  count = 0
  video = nil

  loop do
    count += 1
    videos = get_feed({ :query => 'innocence of muslims', :page => count })
    total += videos.size
    video  = videos.find { |v| v.state && v.state[:reason_code] && v.state[:reason_code].include?('requesterRegion') }

    puts "total: #{total}"

    break if total >= 999 || video
  end

  puts "total: #{total}, count: #{count}"

  if video
    video.public_methods(false).each { |meth| puts "#{meth}: #{video.send(meth)}" }

    f = File.new("./results/hits", 'a+')
    video_to_hash(fields_attributes[:client], video).each { |k,v| f.write "#{k}: #{v}\n" }
    f.close
  end
end