# frozen_string_literal: true

require 'xcknife/json_stream_parser_helper'
require 'set'

module XCKnife
  class EventsAnalyzer
    include JsonStreamParserHelper
    attr_reader :target_class_map, :total_tests

    def self.for(events, relevant_partitions)
      return NullEventsAnalyzer.new if events.nil?

      new(events, relevant_partitions)
    end

    def initialize(events, relevant_partitions)
      @total_tests = 0
      @relevant_partitions = relevant_partitions
      @target_class_map = analyze_events(events)
    end

    def test_target?(target)
      target_class_map.key?(target)
    end

    def test_class?(target, clazz)
      test_target?(target) and target_class_map[target].include?(clazz)
    end

    private

    def analyze_events(events)
      ret = Hash.new { |h, key| h[key] = Set.new }
      each_test_event(events) do |target_name, result|
        next unless @relevant_partitions.include?(target_name)

        @total_tests += 1
        ret[target_name] << result.className
      end
      ret
    end
  end

  # Null object for EventsAnalyzer
  # @ref https://en.wikipedia.org/wiki/Null_Object_pattern
  class NullEventsAnalyzer
    def test_target?(_target)
      true
    end

    def test_class?(_target, _clazz)
      true
    end

    def total_tests
      0
    end
  end
end
