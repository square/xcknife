module XCKnife
  module JsonStreamParserHelper
    extend self

    # Iterates over events, calling block once for each test_target/test event on a events (a parsed json_stream iterable)
    def each_test_event(events, &block)
      current_target = nil
      events.each do |result|
        current_target = result.targetName if result.event == "begin-ocunit"
        if result.test and result.event == "end-test"
          raise XCKnife::StreamParsingError, "No test target defined" if current_target.nil?
          block.call(current_target, normalize_result(result))
        end
      end
    end

    def normalize_result(result)
      if result.totalDuration.is_a?(String)
        result.totalDuration = result.totalDuration.to_f
      end
      result
    end
  end
end
