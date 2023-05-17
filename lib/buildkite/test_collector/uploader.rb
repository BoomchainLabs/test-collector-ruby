# frozen_string_literal: true

module Buildkite::TestCollector
  class Uploader
    MAX_UPLOAD_ATTEMPTS = 3

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

    RETRYABLE_UPLOAD_ERRORS = [
      Net::ReadTimeout,
      Net::OpenTimeout,
      OpenSSL::SSL::SSLError,
      OpenSSL::SSL::SSLErrorWaitReadable,
      EOFError,
      Errno::ETIMEDOUT
    ]

    def self.tracer
      Thread.current[:_buildkite_tracer]
    end

    def self.upload(data)
      return false unless Buildkite::TestCollector.api_token

      http = Buildkite::TestCollector::HTTPClient.new(Buildkite::TestCollector.url)

      Thread.new do
        response = begin
          upload_attempts ||= 0
          http.post_json(data)
        rescue *Buildkite::TestCollector::Uploader::RETRYABLE_UPLOAD_ERRORS => e
          if (upload_attempts += 1) < MAX_UPLOAD_ATTEMPTS
            retry
          end
        end
      end
    end
  end
end
