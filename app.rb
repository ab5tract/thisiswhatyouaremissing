require 'sinatra'
require 'youtube_it'

helpers do
	def client
		@client ||= YouTubeIt::Client.new(
			:username => ENV['YOUTUBE_USERNAME'],
			:password => ENV['YOUTUBE_PASSWORD'],
			:dev_key  => ENV['YOUTUBE_DEV_KEY']
		)
	end
end

get '/' do
	puts client.inspect
end