require 'sinatra'
require 'youtube_it'
require './youtube_it_fix'
require 'active_support/core_ext/date/calculations'
require 'json'
require 'geocoder'

configure :development do
  require './devenv'
end

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
      :feed     => :most_popular,
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

get '/fetch' do
  @hits = get_feed(:page => params[:page]).select { |v| v.restricted_in? params[:country] }

  logger.debug "hits: #{@hits.size}, page: #{params[:page]}, country: #{params[:country]}"

  JSON.dump @hits.map { |video| @video = video; erb :player, :layout => false }
end

get '/' do
  @country_override = params[:country]
  @country_default  = request.location.country_code

  erb :index
end