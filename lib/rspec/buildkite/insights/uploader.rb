# frozen_string_literal: true

require "rspec/core"
require "rspec/expectations"

require "openssl"
require "websocket"

require_relative "tracer"
require_relative "network"
require_relative "session"

require "active_support"
require "active_support/notifications"

require "securerandom"

module RSpec::Buildkite::Insights
  class Uploader
    class Trace
      attr_reader :example, :history
      def initialize(example, history)
        @example = example
        @history = history
      end

      def failure_message
        case example.exception
        when RSpec::Expectations::ExpectationNotMetError
          example.exception.message
        when Exception
          "#{example.exception.class}: #{example.exception.message}"
        end
      end

      def result_state
        case example.execution_result.status
        when :passed; "passed"
        when :failed; "failed"
        when :pending; "skipped"
        end
      end

      def as_json
        {
          scope: example.example_group.metadata[:full_description],
          name: example.description,
          identifier: example.id,
          location: example.location,
          file_name: generate_file_name(example),
          result: result_state,
          failure: failure_message,
          history: history,
        }
      end

      private

      def generate_file_name(example)
        file_path_regex = /^(.*?\.rb)/
        identifier_file_name = example.id[file_path_regex]
        location_file_name = example.location[file_path_regex]

        if identifier_file_name != location_file_name
          # If the identifier and location files are not the same, we assume
          # that the test was run as part of a shared example. If this isn't the
          # case, then there's something we haven't accounted for
          if example.metadata[:shared_group_inclusion_backtrace].any?
            # Taking the last frame in this backtrace will give us the original
            # entry point for the shared example
            example.metadata[:shared_group_inclusion_backtrace].last.inclusion_location[file_path_regex]
          else
            "Unknown"
          end
        else
          identifier_file_name
        end
      end
    end

    def self.traces
      @traces ||= []
    end

    def self.configure
      uploader = self
      session = nil

      RSpec.configure do |config|
        config.around(:each) do |example|
          tracer = RSpec::Buildkite::Insights::Tracer.new

          Thread.current[:_buildkite_tracer] = tracer
          example.run
          Thread.current[:_buildkite_tracer] = nil

          tracer.finalize

          trace = RSpec::Buildkite::Insights::Uploader::Trace.new(example, tracer.history)
          uploader.traces << trace

          session&.write_result(trace)
        end

        config.before(:suite) do
          if RSpec::Buildkite::Insights.api_token
            contact_uri = URI.parse(RSpec::Buildkite::Insights.url)

            http = Net::HTTP.new(contact_uri.host, contact_uri.port)
            http.use_ssl = contact_uri.scheme == "https"

            authorization_header = "Token token=\"#{RSpec::Buildkite::Insights.api_token}\""

            contact = Net::HTTP::Post.new(contact_uri.path, {
              "Authorization" => authorization_header,
              "Content-Type" => "application/json",
            })
            contact.body = {
              # FIXME: Unique identifying attributes of the current build
              run_key: ENV["BUILDKITE_BUILD_ID"] || SecureRandom.uuid,
            }.to_json

            response = http.request(contact)

            if response.is_a?(Net::HTTPSuccess)
              json = JSON.parse(response.body)

              if (socket_url = json["cable"]) && (channel = json["channel"])
                session = Session.new(socket_url, authorization_header, channel)
              end
            end
          end
        end

        config.after(:suite) do
          if filename = RSpec::Buildkite::Insights.filename
            data_set = { results: uploader.traces.map(&:as_json) }

            File.open(filename, "wb") do |f|
              gz = Zlib::GzipWriter.new(f)
              gz.write(data_set.to_json)
              gz.close
            end
          end
        end
      end

      RSpec::Buildkite::Insights::Network.configure

      ActiveSupport::Notifications.subscribe("sql.active_record") do |name, start, finish, id, payload|
        tracer&.backfill(:sql, finish - start, { query: payload[:sql] })
      end
    end

    def self.tracer
      Thread.current[:_buildkite_tracer]
    end
  end
end
