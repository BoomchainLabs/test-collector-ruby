# frozen_string_literal: true

module RSpec::Buildkite::Analytics
  class Object
    module CustomObjectSleep
      def sleep(duration)
        tracer = RSpec::Buildkite::Analytics::Uploader.tracer
        tracer&.enter("sleep")

        super
      ensure
        tracer&.leave
      end
    end

    def self.configure
      ::Object.prepend(CustomObjectSleep)
    end
  end
end
