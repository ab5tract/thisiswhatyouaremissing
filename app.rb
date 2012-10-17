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

  def query_params(params = {})
    {
      :feed     => nil,
      :per_page => 50,
      :page     => 1,
      :time     => 'all_time'
    }.merge(params)
  end

  def get_feed(params = {})
    if feed = params.delete(:feed)
      client.videos_by(feed, query_params(params)).videos
    else
      client.videos_by(query_params(params)).videos
    end
  end
end

get '/reset' do
  session.each { |k,v| session.delete k }; 'OK'
end

get '/fetch' do
  @hits = get_feed(:page => params[:page]).select do |video|
    video.restricted_in?(
      params[:country]       ||
      session[:country_code] ||
      'CN'
    )
  end

  puts "hits: #{@hits.size}, page: #{params[:page]}" if development?

  JSON.dump @hits.map { |video| @video = video; erb :player, :layout => false }
end

get '/' do
  @country = params[:country]
  session[:country_code] ||= request.location.country_code
  puts session[:country_code] if development?
  erb :index
end