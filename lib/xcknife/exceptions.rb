module XCKnife
  # Base error class for xcknife
  XCKnifeError = Class.new(StandardError)

  StreamParsingError = Class.new(XCKnifeError)
end