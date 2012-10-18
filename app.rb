require 'sinatra'
require 'youtube_it'
require './patches/patches'
require 'active_support/core_ext/date/calculations'
require 'json'
require 'geocoder'
require 'facets/enumerable/compact_map'

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
end

get '/fetch' do
  query = {
    :per_page => 50,
    :page     => params[:page],
    :time     => 'all_time'
  }

  players = client.videos_by(query).videos.compact_map do |video|
    @video = video
    erb :player, :layout => false if video.restricted_in? params[:country]
  end

  logger.debug "page: #{params[:page]}, hits: #{players.size}, country: #{params[:country]}"

  JSON.dump players
end

get '/' do
  @country_override = params[:country]
  @country_default  = request.location.country_code

  erb :index
end