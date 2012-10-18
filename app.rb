require 'sinatra'
require 'sinatra/contrib'
require 'youtube_it'
require './patches/patches'
require 'json'
require 'geocoder'
require 'facets/enumerable/compact_map'

configure :development do
  require './devenv'
end

before do
  logger.level     = Logger::DEBUG if development?
  YouTubeIt.logger = logger
end

helpers do
  def development?
    ENV['RACK_ENV'] == 'development'
  end

  def search_words
    [
      'testing',
      'playground',
      'whatever'
    ]
  end

  def client
    @client ||= YouTubeIt::Client.new({
      :username => ENV['YOUTUBE_USERNAME'],
      :password => ENV['YOUTUBE_PASSWORD'],
      :dev_key  => ENV['YOUTUBE_DEV_KEY'],
      :debug    => true
    })
  end
end

get '/fetch' do
  players = client.videos_by(params).videos.compact_map do |video|
    @video = video
    erb :player, :layout => false if video.restricted_in? params[:country]
  end

  logger.debug "\nHITS: #{players.size}\nQUERY: #{params[:query]}\nPAGE: #{params[:page]}\nCOUNTRY: #{params[:country]}\n"

  JSON.dump players
end

get '/' do
  @country_override = params[:country]
  @country_default  = request.location.country_code
  @search_words     = JSON.dump search_words

  erb :index
end