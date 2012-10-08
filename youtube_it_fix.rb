class YouTubeIt
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
end