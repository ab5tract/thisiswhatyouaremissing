class YouTubeIt
  class Client
    def videos_by(params, options={})
      request_params = params.respond_to?(:to_hash) ? params : options
      request_params[:page] = integer_or_default(request_params[:page], 1)

      request_params[:dev_key] = @dev_key if @dev_key

      unless request_params[:max_results]
        request_params[:max_results] = integer_or_default(request_params[:per_page], 50)
      end

      unless request_params[:offset]
        request_params[:offset] = calculate_offset(request_params[:page], request_params[:max_results] )
      end

      if params.respond_to?(:to_hash) and not params[:user]
        request = YouTubeIt::Request::VideoSearch.new(request_params)
      elsif (params.respond_to?(:to_hash) && params[:user]) || (params == :favorites)
        request = YouTubeIt::Request::UserSearch.new(params, request_params)
      else
        request = YouTubeIt::Request::StandardSearch.new(params, request_params)
      end

      logger.debug "Submitting request [url=#{request.url}]." if @legacy_debug_flag
      parser = YouTubeIt::Parser::VideosFeedParser.new(request.url)
      parser.parse
    end
  end

  module Request
    module FieldSearch
      def default_entry_fields
        "id"
      end

      def fields_to_params(fields)
        return "" unless fields

        fields_param = [default_fields]

        if fields[:recorded]
          if fields[:recorded].is_a? Range
            fields_param << "entry(xs:date(yt:recorded) > xs:date('#{formatted_date(fields[:recorded].first)}') and xs:date(yt:recorded) < xs:date('#{formatted_date(fields[:recorded].last)}'))"
          else
            fields_param << "entry(xs:date(yt:recorded) = xs:date('#{formatted_date(fields[:recorded])}'))"
          end
        end

        if fields[:published]
          if fields[:published].is_a? Range
            fields_param << "entry(xs:dateTime(published) > xs:dateTime('#{formatted_date(fields[:published].first)}T00:00:00') and xs:dateTime(published) < xs:dateTime('#{formatted_date(fields[:published].last)}T00:00:00'))"
          else
            fields_param << "entry(xs:date(published) = xs:date('#{formatted_date(fields[:published])}'))"
          end
        end

        if fields[:view_count]
          fields_param << "entry(yt:statistics/@viewCount > #{fields[:view_count]})"
        end
        
        if fields[:entry]
          fields_param << "entry(#{default_entry_fields},#{fields[:entry]})"
        end


        return "&fields=#{URI.escape(fields_param.join(","))}"
      end
    end
  end

  module Parser
    class VideoFeedParser < FeedParser
      protected
      def parse_entry(entry)
        video_id = entry.at("id").text
        published_at = entry.at("published") ? Time.parse(entry.at("published").text) : nil
        uploaded_at = entry.at_xpath("media:group/yt:uploaded") ? Time.parse(entry.at_xpath("media:group/yt:uploaded").text) : nil
        updated_at = entry.at("updated") ? Time.parse(entry.at("updated").text) : nil
        recorded_at = entry.at_xpath("yt:recorded") ? Time.parse(entry.at_xpath("yt:recorded").text) : nil

        # parse the category and keyword lists
        categories = []
        keywords = []
        entry.css("category").each do |category|
          # determine if  it's really a category, or just a keyword
          scheme = category["scheme"]
          if (scheme =~ /\/categories\.cat$/)
            # it's a category
            categories << YouTubeIt::Model::Category.new(
                            :term => category["term"],
                            :label => category["label"])

          elsif (scheme =~ /\/keywords\.cat$/)
            # it's a keyword
            keywords << category["term"]
          end
        end

        title = entry.at("title").text
        html_content = nil #entry.at("content") ? entry.at("content").text : nil

        # parse the author
        author_element = entry.at("author")
        author = nil
        if author_element
          author = YouTubeIt::Model::Author.new(
                     :name => author_element.at("name").text,
                     :uri => author_element.at("uri").text)
        end
        media_group = entry.at_xpath('media:group')

        ytid = nil
        unless media_group.at_xpath("yt:videoid").nil?
          ytid = media_group.at_xpath("yt:videoid").text
        end

        # if content is not available on certain region, there is no media:description, media:player or yt:duration
        description = ""
        unless media_group.at_xpath("media:description").nil?
          description = media_group.at_xpath("media:description").text
        end

        # if content is not available on certain region, there is no media:description, media:player or yt:duration
        duration = 0
        unless media_group.at_xpath("yt:duration").nil?
          duration = media_group.at_xpath("yt:duration")["seconds"].to_i
        end

        # if content is not available on certain region, there is no media:description, media:player or yt:duration
        player_url = ""
        unless media_group.at_xpath("media:player").nil?
          player_url = media_group.at_xpath("media:player")["url"]
        end

        unless media_group.at_xpath("yt:aspectRatio").nil?
          widescreen = media_group.at_xpath("yt:aspectRatio").text == 'widescreen' ? true : false
        end

        media_content = []
        media_group.xpath("media:content").each do |mce|
          media_content << parse_media_content(mce)
        end

        # parse thumbnails
        thumbnails = []
        media_group.xpath("media:thumbnail").each do |thumb_element|
          # TODO: convert time HH:MM:ss string to seconds?
          thumbnails << YouTubeIt::Model::Thumbnail.new(
                          :url    => thumb_element["url"],
                          :height => thumb_element["height"].to_i,
                          :width  => thumb_element["width"].to_i,
                          :time   => thumb_element["time"])
        end

        rating_element = entry.at_xpath("gd:rating")
        extended_rating_element = entry.at_xpath("yt:rating")

        rating = nil
        if rating_element
          rating_values = {
            :min         => rating_element["min"].to_i,
            :max         => rating_element["max"].to_i,
            :rater_count => rating_element["numRaters"].to_i,
            :average     => rating_element["average"].to_f
          }

          if extended_rating_element
            rating_values[:likes] = extended_rating_element["numLikes"].to_i
            rating_values[:dislikes] = extended_rating_element["numDislikes"].to_i
          end

          rating = YouTubeIt::Model::Rating.new(rating_values)
        end

        if (el = entry.at_xpath("yt:statistics"))
          view_count, favorite_count = el["viewCount"].to_i, el["favoriteCount"].to_i
        else
          view_count, favorite_count = 0,0
        end

        comment_feed = entry.at_xpath('gd:comments/gd:feedLink[@rel="http://gdata.youtube.com/schemas/2007#comments"]')
        comment_count = comment_feed ? comment_feed['countHint'].to_i : 0

        access_control = entry.xpath('yt:accessControl').map do |e|
          { e['action'] => e['permission'] }
        end.compact.reduce({},:merge)

        noembed     = entry.at_xpath("yt:noembed") ? true : false
        safe_search = entry.at_xpath("media:rating") ? true : false

        if entry.namespaces['xmlns:georss'] and where = entry.at_xpath("georss:where")
          position = where.at_xpath("gml:Point").at_xpath("gml:pos").text
          latitude, longitude = position.split.map &:to_f
        end

        if entry.namespaces['xmlns:app']
          control = entry.at_xpath("app:control")
          state = { :name => "published" }
          if control && control.at_xpath("yt:state")
            state = {
              :name        => control.at_xpath("yt:state")["name"],
              :reason_code => control.at_xpath("yt:state")["reasonCode"],
              :help_url    => control.at_xpath("yt:state")["helpUrl"],
              :copy        => control.at_xpath("yt:state").text
            }
          end
        end

        insight_uri = (entry.at_xpath('xmlns:link[@rel="http://gdata.youtube.com/schemas/2007#insight.views"]')['href'] rescue nil)

        perm_private = media_group.at_xpath("yt:private") ? true : false

        media_restriction = media_group.at_xpath("media:restriction")
        restriction = media_restriction.text.split if media_restriction && media_restriction[:relationship] == 'deny'

        YouTubeIt::Model::Video.new(
          :video_id       => video_id,
          :published_at   => published_at,
          :updated_at     => updated_at,
          :uploaded_at    => uploaded_at,
          :recorded_at    => recorded_at,
          :categories     => categories,
          :keywords       => keywords,
          :title          => title,
          :html_content   => html_content,
          :author         => author,
          :description    => description,
          :duration       => duration,
          :media_content  => media_content,
          :player_url     => player_url,
          :thumbnails     => thumbnails,
          :rating         => rating,
          :view_count     => view_count,
          :favorite_count => favorite_count,
          :comment_count  => comment_count,
          :access_control => access_control,
          :widescreen     => widescreen,
          :noembed        => noembed,
          :safe_search    => safe_search,
          :position       => position,
          :latitude       => latitude,
          :longitude      => longitude,
          :state          => state,
          :insight_uri    => insight_uri,
          :unique_id      => ytid,
          :perm_private   => perm_private,
          :restriction    => restriction)
      end
    end
  end

  module Model
    class Video < YouTubeIt::Record
      attr_reader :restriction

      def restricted_in?(country_code)
        restriction && restriction.include?(country_code)
      end
    end
  end
end