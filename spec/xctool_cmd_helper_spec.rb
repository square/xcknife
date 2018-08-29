require 'spec_helper'

describe XCKnife::XCToolCmdHelper do
  include XCKnife::XCToolCmdHelper

  it "can compute xctool's -only argument list for a single partition" do
    result = xctool_only_arguments(
      { "TargetOneOnPartition1" => ["TestClass1", "TestClassX"],
        "TargetTwoOnPartition1" => ["TestClassY"]
      })
    expect(result).to eq(%w[-only TargetOneOnPartition1:TestClass1,TestClassX -only TargetTwoOnPartition1:TestClassY])
  end

  it "can compute xcodebuilds's -only argument list for a single partition" do
    result = xcodebuild_only_arguments(
      { "TargetOneOnPartition1" => ["TestClass1", "TestClassX"],
        "TargetTwoOnPartition1" => ["TestClassY"]
      })
    expect(result).to eq(%w[
      -only-testing:TargetOneOnPartition1/TestClass1
      -only-testing:TargetOneOnPartition1/TestClassX
      -only-testing:TargetTwoOnPartition1/TestClassY])
  end

  it "can compute xcodebuilds's -only argument list for a single partition when given a set of all partitions" do
    partition = {
      "TargetOneOnPartition1" => ["TestClass1", "TestClassX"],
      "TargetTwoOnPartition1" => ["TestClassY"],
    }
    result = xcodebuild_only_arguments(partition, [partition])
    expect(result).to eq(%w[
      -only-testing:TargetOneOnPartition1
      -only-testing:TargetTwoOnPartition1])

    partition_two = {
      "TargetOneOnPartition1" => %w[TestClassZ],
      "TargetOneOnPartition2" => %w[TestClassA],
    }
    result = xcodebuild_only_arguments(partition, [partition, partition_two])
    expect(result).to eq(%w[
      -only-testing:TargetTwoOnPartition1
      -only-testing:TargetOneOnPartition1/TestClass1
      -only-testing:TargetOneOnPartition1/TestClassX
    ])

    result = xcodebuild_only_arguments(partition_two, [partition, partition_two])
    expect(result).to eq(%w[
      -only-testing:TargetOneOnPartition2
      -only-testing:TargetOneOnPartition1/TestClassZ
    ])
  end

  it "can use output type as an argument" do
    result = only_arguments(:xctool,
      { "TargetOneOnPartition1" => ["TestClass1", "TestClassX"],
        "TargetTwoOnPartition1" => ["TestClassY"]
      })
    expect(result).to eq(%w[-only TargetOneOnPartition1:TestClass1,TestClassX -only TargetTwoOnPartition1:TestClassY])
  end
end
