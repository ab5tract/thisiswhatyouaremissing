require 'sinatra'
require 'sinatra/contrib'
require 'youtube_it'
require './patches/patches'
require 'json'
require 'geocoder'
require 'facets/enumerable/compact_map'
require 'facets/string/titlecase'
require 'nokogiri'

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
    File.open('./data/searchwords.txt') { |f| f.readlines.each { |l| l.chomp! } }
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
    erb :player, :layout => false if video.restricted_in?(params[:country]) && !video.is_rental
  end

  logger.debug "\nHITS: #{players.size}\nQUERY: #{params[:query]}\nPAGE: #{params[:page]}\nCOUNTRY: #{params[:country]}\n"

  JSON.dump players
end

get '/' do
  @country      = request.location && request.location.country_code
  @search_words = JSON.dump search_words

  erb :index
end

get '/about' do
  erb :about, :layout => false
end

get '/visa' do
  erb :visa, :layout => false
end