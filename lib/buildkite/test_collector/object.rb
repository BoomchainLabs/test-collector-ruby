# frozen_string_literal: true

module Buildkite::TestCollector
  class Object
    module CustomObjectSleep
      def sleep(duration)
        tracer = Buildkite::TestCollector::Uploader.tracer
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
