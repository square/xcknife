# frozen_string_literal: true

module XCKnife
  module JsonStreamParserHelper
    extend self

    # Iterates over events, calling block once for each test_target/test event on a events (a parsed json_stream iterable)
    def each_test_event(events, &block)
      current_target = nil
      events.each do |result|
        current_target = result.targetName if result.event == 'begin-ocunit'
        next unless result.test && (result.event == 'end-test')
        raise XCKnife::StreamParsingError, 'No test target defined' if current_target.nil?

        block.call(current_target, normalize_result(result))
      end
    end

    def normalize_result(result)
      result.totalDuration = result.totalDuration.to_f if result.totalDuration.is_a?(String)
      result
    end
  end
end
