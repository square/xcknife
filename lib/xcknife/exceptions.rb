# frozen_string_literal: true

module XCKnife
  # Base error class for xcknife
  XCKnifeError = Class.new(RuntimeError)

  TestDumpError = Class.new(XCKnifeError)

  StreamParsingError = Class.new(XCKnifeError)
end
