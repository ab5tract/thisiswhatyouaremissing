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
end

get '/fetch' do
  JSON.dump client.videos_by({
    :per_page => 50,
    :page     => params[:page],
    :time     => 'all_time'
  }).videos.map { |v| @video = v; erb :player, :layout => false if v.restricted_in?(params[:country]) }.compact
end

get '/' do
  @country_override = params[:country]
  @country_default  = request.location.country_code

  erb :index
end