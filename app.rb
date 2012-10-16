require 'sinatra'
require 'youtube_it'
require './youtube_it_fix'
require 'active_support/core_ext/date/calculations'
require 'json'
require 'geocoder'

configure :development do
  require './devenv'
end

enable :sessions

before do
  if development?
    logger.level     = Logger::DEBUG
    YouTubeIt.logger = logger
  end
end

helpers do
  def development?
    ENV['RACK_ENV'] == 'development'
  end

  def client
    @client ||= YouTubeIt::Client.new({
      :username => ENV['YOUTUBE_USERNAME'],
      :password => ENV['YOUTUBE_PASSWORD'],
      :dev_key  => ENV['YOUTUBE_DEV_KEY'],
      :debug    => development?
    })
  end

  def projecting?
    false
  end

  def fields_param
    projecting? ? { :fields => { :entry => fields_attributes[:server].join(',') } } : {}
  end

  def query_params(params = {})
    {
      :feed     => nil,
      :per_page => 50,
      :page     => 1,
      :time     => 'all_time'
    }.merge(params).merge(fields_param)
  end

  def fields_attribute_mapping
    {
      :title        => 'title',
      :published_at => 'published',
      :view_count   => 'yt:statistics(@viewCount)',
      :state        => 'app:control(yt:state)',
      :player_url   => 'media:group(media:player(@url))',
      :restriction  => 'media:group(media:restriction)'
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

  def get_feed(params = {})
    if feed = params.delete(:feed)
      client.videos_by(feed, query_params(params)).videos
    else
      client.videos_by(query_params(params)).videos
    end
  end

  def video_to_hash(atts, video)
    atts.reduce({}) { |hash, att| hash[att] = video.send(att); hash }
  end

  def fields_attributes
    @fields_attributes ||= generate_fields_attributes(fields_attribute_mapping)
  end

  def feed_types
    [
      nil,
      :top_rated,
      :top_favorites,
      :most_discussed,
      :most_responded
    ]
  end

  def time_spans
    [
      'all_time',
      'this_month',
      'this_week',
      'today'
    ]
  end
end

get '/reset' do
  session.each { |k,v| session.delete k }; 'OK'
end

get '/fetch' do
  @hits = []

  session[:page]      ||= 0
  session[:feed_type] ||= 0
  session[:time_span] ||= 0

  session[:page] += 1

  @hits += get_feed(
    :feed => feed_types[session[:feed_type]],
    :page => session[:page],
    :time => time_spans[session[:time_span]]
  ).select do |v|
    v.restriction && v.restriction.include?(
      params[:country]       ||
      session[:country_code] ||
      'CN'
    )
  end

  puts "hits: #{@hits.size}, time_span: #{time_spans[session[:time_span]]}, feed_type: #{feed_types[session[:feed_type]]}, page: #{session[:page]}" if development?
  
  if session[:page] >= 20
    session[:feed_type] += 1
    session[:page] = 0

    if session[:feed_type] >= feed_types.size
      session[:feed_type] = 0
      session[:time_span] += 1
      

      if session[:time_span] >= time_spans.size
        session[:page]      = 0
        session[:feed_type] = 0
        session[:time_span] = 0
      end
    end
  end

  JSON.dump @hits.map { |video| @video = video; erb :player, :layout => false }
end

get '/' do
  @country = params[:country]
  session[:country_code] ||= request.location.country_code
  puts session[:country_code] if development?
  erb :index
end

get '/test' do
  get_feed(:feed => :most_popular).each do |video|
    puts video_to_hash(fields_attributes[:client], video)
  end
  'hi'
end