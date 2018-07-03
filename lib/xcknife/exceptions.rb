module XCKnife
  # Base error class for xcknife
  XCKnifeError = Class.new(StandardError)

  TestDumpError = Class.new(XCKnifeError)

  StreamParsingError = Class.new(XCKnifeError)
end
