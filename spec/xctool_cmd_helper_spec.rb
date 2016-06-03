require 'spec_helper'

describe XCKnife::XCToolCmdHelper do
  include XCKnife::XCToolCmdHelper

  it "can compute the -only argument list for a single partition" do
    result = xctool_only_arguments(
      { "TargetOneOnPartition1" => ["TestClass1", "TestClassX"],
        "TargetTwoOnPartition1" => ["TestClassY"]
      })
    expect(result).to eq(%w[-only TargetOneOnPartition1:TestClass1,TestClassX -only TargetTwoOnPartition1:TestClassY])
  end
end
