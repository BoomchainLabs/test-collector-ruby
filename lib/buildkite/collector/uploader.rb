# frozen_string_literal: true

require "openssl"
require "websocket"

require_relative "tracer"
require_relative "network"
require_relative "object"
require_relative "session"
require_relative "ci"
require_relative "http_client"

require "active_support"
require "active_support/notifications"

require "securerandom"

module Buildkite::Collector
  class Uploader
    def self.traces
      @traces ||= {}
    end

    REQUEST_EXCEPTIONS = [
      URI::InvalidURIError,
      Net::HTTPBadResponse,
      Net::HTTPHeaderSyntaxError,
      Net::ReadTimeout,
      Net::OpenTimeout,
      OpenSSL::SSL::SSLError,
      OpenSSL::SSL::SSLErrorWaitReadable,
      EOFError
    ]

    def self.configure
      Buildkite::Collector.logger.debug("hello from main thread")

      if Buildkite::Collector.api_token
        http = Buildkite::Collector::HTTPClient.new(Buildkite::Collector.url)

        response = begin
          http.post
        rescue *Buildkite::Collector::Uploader::REQUEST_EXCEPTIONS => e
          Buildkite::Collector.logger.error "Buildkite Test Analytics: Error communicating with the server: #{e.message}"
        end

        return unless response

        case response.code
        when "401"
          Buildkite::Collector.logger.info "Buildkite Test Analytics: Invalid Suite API key. Please double check your Suite API key."
        when "200"
          json = JSON.parse(response.body)

          if (socket_url = json["cable"]) && (channel = json["channel"])
            Buildkite::Collector.session = Buildkite::Collector::Session.new(socket_url, http.authorization_header, channel)
          end
        else
          request_id = response.to_hash["x-request-id"]
          Buildkite::Collector.logger.info "rspec-buildkite-analytics could not establish an initial connection with Buildkite. You may be missing some data for this test suite, please contact support."
        end
      else
        if !!ENV["BUILDKITE_BUILD_ID"]
          Buildkite::Collector.logger.info "Buildkite Test Analytics: No Suite API key provided. You can get the API key from your Suite settings page."
        end
      end
    end

    def self.tracer
      Thread.current[:_buildkite_tracer]
    end
  end
end
