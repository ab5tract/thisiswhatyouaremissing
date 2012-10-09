require 'sinatra'
require 'youtube_it'
require './youtube_it_fix'
require 'active_support/core_ext/date/calculations'
require 'json'

configure :development do
  require './devenv'
end

enable :sessions

helpers do
  def development?
    ENV['RACK_ENV'] == :development
  end

  def client
    args = {
      :username => ENV['YOUTUBE_USERNAME'],
      :password => ENV['YOUTUBE_PASSWORD'],
      :dev_key  => ENV['YOUTUBE_DEV_KEY']
    }
    args.merge(:debug => true) if development?

    @client ||= YouTubeIt::Client.new(args)
  end

  def projecting?
    false
  end

  def fields_param
    projecting? ? { :fields => { :entry => fields_attributes[:server].join(',') } } : {}
  end

  def query_params(params = {})
    {
      :per_page => 50,
      :page     => 1,
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

  def get_feed(type, params)
    if type
      client.videos_by(type, query_params(params)).videos
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
  session[:page]      = 0
  session[:feed_type] = 0
  session[:time_span] = 0

  'OK'
end

get '/fetch' do
  @hits = []

  session[:page]      ||= 0
  session[:feed_type] ||= 0
  session[:time_span] ||= 0

  session[:page] += 1

  videos = get_feed(feed_types[session[:feed_type]], :page => session[:page], :time => time_spans[session[:time_span]])

  @hits += videos.select { |v| v.restriction && v.restriction.include?(params[:country] || 'CN') }

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
  erb :index
end