# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

require_relative "base"
require_relative "../error"

module VectorAmp
  module Transport
    class HTTP < Base
      DEFAULT_TIMEOUT = 60

      def initialize(base_url:, api_key:, timeout: DEFAULT_TIMEOUT)
        @base_uri = URI(base_url)
        @api_key = api_key
        @timeout = timeout
      end

      def request(method, path, query: nil, body: nil, headers: {}, stream: false, raw: false, &block)
        uri = build_uri(path, query)
        request = build_request(method, uri, body, headers)

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @timeout, read_timeout: @timeout) do |http|
          if stream
            return stream_response(http, request, &block)
          end

          response = http.request(request)
          handle_response(response, raw: raw)
        end
      end

      private

      def build_uri(path, query)
        uri = @base_uri.dup
        base_path = uri.path.to_s.chomp("/")
        relative = path.to_s.start_with?("/") ? path : "/#{path}"
        uri.path = "#{base_path}#{relative}"
        params = query&.compact
        uri.query = URI.encode_www_form(params) if params && !params.empty?
        uri
      end

      def build_request(method, uri, body, headers)
        klass = Net::HTTP.const_get(method.to_s.capitalize)
        request = klass.new(uri)
        request["Accept"] = "text/event-stream, application/json"
        request["Content-Type"] = "application/json" if body
        request["User-Agent"] = "vector_amp-ruby/#{VectorAmp::VERSION}"
        request["X-API-Key"] = @api_key
        headers.each { |key, value| request[key.to_s] = value }
        request.body = JSON.generate(body) if body
        request
      end

      def handle_response(response, raw: false)
        return follow_redirect(response, raw: raw) if redirect?(response)
        return response.body if raw && response.is_a?(Net::HTTPSuccess)

        parsed = parse_body(response.body)
        return parsed if response.is_a?(Net::HTTPSuccess)

        message = parsed.is_a?(Hash) ? (parsed["error"] || parsed["message"] || response.message) : response.message
        raise APIError.new(message, status: response.code.to_i, body: parsed, headers: response.to_hash)
      end

      def redirect?(response)
        response.is_a?(Net::HTTPRedirection) && response["location"]
      end

      def follow_redirect(response, raw:)
        uri = URI(response["location"])
        uri = @base_uri + response["location"] unless uri.absolute?
        request = build_request(:get, uri, nil, {})
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @timeout, read_timeout: @timeout) do |http|
          handle_response(http.request(request), raw: raw)
        end
      end

      def stream_response(http, request)
        http.request(request) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            body = response.body || ""
            parsed = parse_body(body)
            message = parsed.is_a?(Hash) ? (parsed["error"] || parsed["message"] || response.message) : response.message
            raise APIError.new(message, status: response.code.to_i, body: parsed, headers: response.to_hash)
          end

          parser = SSEParser.new
          response.read_body do |chunk|
            parser.feed(chunk) do |event|
              yield event if block_given?
            end
          end
          parser.flush { |event| yield event if block_given? }
        end
        nil
      end

      def parse_body(body)
        return nil if body.nil? || body.empty?

        JSON.parse(body)
      rescue JSON::ParserError
        body
      end
    end

    class SSEParser
      def initialize
        @buffer = +""
      end

      def feed(chunk)
        @buffer << chunk
        while (index = @buffer.index(/\r?\n\r?\n/))
          frame = @buffer.slice!(0...index)
          @buffer.sub!(/\A\r?\n\r?\n/, "")
          emit(frame) { |event| yield event }
        end
      end

      def flush
        emit(@buffer) { |event| yield event } unless @buffer.empty?
        @buffer.clear
      end

      private

      def emit(frame)
        data = frame.each_line.filter_map do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?(":")
          next unless stripped.start_with?("data:")

          stripped.delete_prefix("data:").strip
        end.join("\n")
        return if data.empty? || data == "[DONE]"

        yield JSON.parse(data)
      rescue JSON::ParserError
        yield data
      end
    end
  end
end
