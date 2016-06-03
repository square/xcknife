require 'spec_helper'

describe XCKnife::StreamParser do
  context 'test_time_for_partitions' do
    subject { XCKnife::StreamParser.new(2, [["TestTarget1"], ["TestTarget2"]]) }

    it 'decide how many shards each partition set needs' do
      stream = [xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1"),
        xctool_target_event("TestTarget2"),
        xctool_test_event("ClassTest2", "test1")
      ]
      result = subject.test_time_for_partitions(stream)
      expect(result).to eq([{ "TestTarget1" => { "ClassTest1" => 1000 } },
        { "TestTarget2" => { "ClassTest2" => 1000 } }])
    end

    it 'aggretates the times at the class level' do
      stream_parser = XCKnife::StreamParser.new(2, [["TestTarget1"]])
      stream = [xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1", 1.0),
        xctool_test_event("ClassTest1", "test2", 2.0)
      ]
      result = stream_parser.test_time_for_partitions(stream)
      expect(result).to eq([{ "TestTarget1" => { "ClassTest1" => 3000 } }])
    end

    it 'works with multiple partitions' do
      stream_parser = XCKnife::StreamParser.new(2, [["TestTarget1"], ["TestTarget2"], ["TestTarget3"]])

      stream = [xctool_target_event("TestTarget1"),
        xctool_test_event("Class1", "test1"),
        xctool_target_event("TestTarget2"),
        xctool_test_event("Class2", "test1"),
        xctool_target_event("TestTarget3"),
        xctool_test_event("Class3", "test1"),
      ]
      result = stream_parser.test_time_for_partitions(stream)
      expect(result).to eq([{ "TestTarget1" => { "Class1" => 1000 } },
        { "TestTarget2" => { "Class2" => 1000 } },
        { "TestTarget3" => { "Class3" => 1000 } }])
    end

    it 'allows the same target to be listed on multiple partitions' do
      stream_parser = XCKnife::StreamParser.new(2, [["TestTarget1"], ["TestTarget2", "TestTarget1"]])
      stream = [xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1"),
        xctool_target_event("TestTarget2"),
        xctool_test_event("ClassTest2", "test1"),
      ]
      result = stream_parser.test_time_for_partitions(stream)
      expect(result).to eq([{ "TestTarget1" => { "ClassTest1" => 1000 } },
        { "TestTarget2" => { "ClassTest2" => 1000 },
          "TestTarget1" => { "ClassTest1" => 1000 }
        }])
    end

    it 'raises error when an empty partition is specified' do
      stream_parser = XCKnife::StreamParser.new(1, [["TestTarget1"]])
      expect { stream_parser.test_time_for_partitions([]) }.to raise_error(XCKnife::XCKnifeError, 'The following partition has no tests: ["TestTarget1"]')
    end
  end

  context 'provided historical events' do
    subject { XCKnife::StreamParser.new(2, [["TestTarget1", "TestTarget2", "TestTarget3", "NewTestTarget1"]]) }

    it 'ignores test targets not present on current events' do
      historical_events = [xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1"),
        xctool_test_event("ClassTest1", "test2"),
        xctool_target_event("TestTarget2"),
        xctool_test_event("ClassTest2", "test1"),
        xctool_test_event("ClassTest2", "test2")
      ]
      current_events = [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1")
      ]
      result = subject.test_time_for_partitions(historical_events, current_events)
      expect(result).to eq([{ "TestTarget1" => { "ClassTest1" => 2000 } }])
      expect(subject.stats.to_h).to eq({historical_total_tests: 4, current_total_tests: 1, class_extrapolations: 0, target_extrapolations: 0})
    end


    it 'ignores test classes not present on current events' do
      historical_events = [xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1"),
        xctool_test_event("ClassTest1", "test2"),
        xctool_test_event("ClassTest2", "test1"),
        xctool_test_event("ClassTest2", "test2")
      ]
      current_events = [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1")
      ]
      result = subject.test_time_for_partitions(historical_events, current_events)
      expect(result).to eq([{ "TestTarget1" => { "ClassTest1" => 2000 } }])
      expect(subject.stats.to_h).to eq({historical_total_tests: 4, current_total_tests: 1, class_extrapolations: 0, target_extrapolations: 0})
    end

    it 'extrapolates for new test targets' do
      historical_events = [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1")
      ]
      current_events = [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1"),
        xctool_target_event("NewTestTargetButNotRelevant"),
        xctool_test_event("ClassTest10", "test1")
      ]
      result = subject.test_time_for_partitions(historical_events, current_events)
      expect(result.to_set).to eq([{
        "TestTarget1" => { "ClassTest1" => 1000 }
      }
      ].to_set)
      expect(subject.stats.to_h).to eq({historical_total_tests: 1, current_total_tests: 1, class_extrapolations: 0, target_extrapolations: 0})
    end

    it 'extrapolates for new test classes' do
      historical_events = [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1", 1.0),
        xctool_test_event("ClassTest2", "test2", 5.0),
        xctool_test_event("ClassTest3", "test3", 10000.0)
      ]
      current_events = historical_events + [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest2", "test2"),
        xctool_test_event("ClassTestNew", "test1")
      ]
      result = subject.test_time_for_partitions(historical_events, current_events)
      median = 5000
      expect(result).to eq([{
        "TestTarget1" =>
          {
            "ClassTest1" => 1000,
            "ClassTest2" => 5000,
            "ClassTest3" => 10000000,
            "ClassTestNew" => median
          },
      }])
      expect(subject.stats.to_h).to eq({historical_total_tests: 3, current_total_tests: 5, class_extrapolations: 1, target_extrapolations: 0})
    end

    it "ignores test classes that don't belong to relevant targets" do
      historical_events = [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1", 1.0),
        xctool_test_event("ClassTest2", "test2", 5.0),
        xctool_test_event("ClassTest3", "test3", 10000.0)
      ]
      current_events = historical_events + [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest2", "test2"),
        xctool_test_event("ClassTestNew", "test1")
      ]
      result = subject.test_time_for_partitions(historical_events, current_events)
      median = 5000
      expect(result).to eq([{
        "TestTarget1" =>
          {
            "ClassTest1" => 1000,
            "ClassTest2" => 5000,
            "ClassTest3" => 10000000,
            "ClassTestNew" => median
          },
      }])
      expect(subject.stats.to_h).to eq({historical_total_tests: 3, current_total_tests: 5, class_extrapolations: 1, target_extrapolations: 0})
    end
  end

  context 'provided an empty set of applicable historical events' do
    subject { XCKnife::StreamParser.new(2, [["TestTarget1", "TestTarget2", "TestTarget3", "NewTestTarget1"]]) }

    let(:empty_historical_events) { [] }
    let(:default_extrapolated_duration) { XCKnife::StreamParser::DEFAULT_EXTRAPOLATED_DURATION }

    it 'extrapolates the test target duration and classes get extrapolated' do
      current_events = [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1")
      ]
      result = subject.test_time_for_partitions(empty_historical_events, current_events)
      expect(result).to eq([{ "TestTarget1" => { "ClassTest1" => default_extrapolated_duration } }])
    end

    it 'extrapolates the test target to different classes' do
      effectively_empty_historical_events = [
        xctool_target_event("TestTarget2"),
        xctool_test_event("IgnoredClass", "ignoredTest"),
      ]
      current_events = [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest1", "test1"),
        xctool_test_event("ClassTest2", "test2")
      ]
      result = subject.test_time_for_partitions(effectively_empty_historical_events, current_events)
      duration = default_extrapolated_duration
      expect(result).to eq([{ "TestTarget1" => { "ClassTest1" => duration, "ClassTest2" => duration } }])
    end

    it "can handle multiple test targets and test classes" do
      current_events = [
        xctool_target_event("TestTarget1"),
        xctool_test_event("ClassTest11", "test1"),
        xctool_test_event("ClassTest12", "test1"),
        xctool_test_event("ClassTest13", "test1"),
        xctool_target_event("TestTarget2"),
        xctool_test_event("ClassTest21", "test1"),
        xctool_test_event("ClassTest22", "test1"),
        xctool_test_event("ClassTest23", "test1"),
        xctool_target_event("TestTarget3"),
        xctool_test_event("ClassTest31", "test1"),
        xctool_test_event("ClassTest32", "test1"),
        xctool_test_event("ClassTest33", "test1"),
      ]
      result = subject.test_time_for_partitions(empty_historical_events, current_events)
      duration = default_extrapolated_duration
      expect(result).to eq(
        [
          {
            "TestTarget1" => { "ClassTest11" => duration, "ClassTest12" => duration, "ClassTest13" => duration },
            "TestTarget2" => { "ClassTest21" => duration, "ClassTest22" => duration, "ClassTest23" => duration },
            "TestTarget3" => { "ClassTest31" => duration, "ClassTest32" => duration, "ClassTest33" => duration } }]
      )
    end
  end

  it "can split_machines_proportionally" do
    stream_parser = XCKnife::StreamParser.new(5, [["TargetOnPartition1"], ["TargetOnPartition2"]])
    result = stream_parser.split_machines_proportionally([
      { "TargetOnPartition1" => { "TestClass1" => 500, "TestClass2" => 500 } },
      { "TargetOnPartition2" => { "TestClass3" => 1000, "TestClass4" => 1000, "TestClass5" => 1000, "TestClass6" => 1000 } }])
    expect(result.map(&:number_of_shards)).to eq([1, 4])
  end

  it "can split_machines_proportionally even when in the presence of large imbalances" do
    stream_parser = XCKnife::StreamParser.new(5, [["TargetOnPartition1"], ["TargetOnPartition2"], ["TargetOnPartition3"]])
    result = stream_parser.split_machines_proportionally([{ "TargetOnPartition1" => { "TestClass1" => 1 } },
      { "TargetOnPartition2" => { "TestClass2" => 1} },
      { "TargetOnPartition3" => { "TestClass3" => 1000, "TestClass4" => 1000, "TestClass5" => 1000} }])
    expect(result.map(&:number_of_shards)).to eq([1, 1, 3])
  end


  it "should never let partition_sets have less than 1 machine alocated to them" do
    stream_parser = XCKnife::StreamParser.new(3, [["TestTarget1"], ["TestTarget2"]])
    result = stream_parser.split_machines_proportionally([{ "TargetOnPartition1" => { "TestClass1" => 1 } },
      { "TargetOnPartition2" => { "TestClass2" => 2000, "TestClass3" => 2000 } }])
    expect(result.map(&:number_of_shards)).to eq([1, 2])
  end


  context 'test_time_for_partitions' do
    it "partitions the test classes accross the number of machines" do
      stream_parser = XCKnife::StreamParser.new(2, [["Test Target"]])
      partition = { "Test Target" => { "Class1" => 1000, "Class2" => 1000, "Class3" => 2000 } }
      shards = stream_parser.compute_single_shards(2, partition).map(&:test_time_map)
      expect(shards.size).to eq 2
      first_shard, second_shard = shards.sort_by { |map| map.values.flatten.size }
      expect(first_shard.keys).to eq(["Test Target"])
      expect(first_shard.values).to eq([["Class3"]])

      expect(second_shard.keys).to eq(["Test Target"])
      expect(second_shard.values.map(&:to_set)).to eq([["Class1", "Class2"].to_set])
    end

    it "partitions the test, across targets" do
      stream_parser = XCKnife::StreamParser.new(2, [["Test Target1", "Test Target2", "Test Target3"]])
      partition = { "Test Target1" => { "Class1" => 1000 },
        "Test Target2" => { "Class2" => 1000 },
        "Test Target3" => { "Class3" => 2000 } }
      shards = stream_parser.compute_single_shards(2, partition).map(&:test_time_map)
      expect(shards.size).to eq 2
      first_shard, second_shard = shards.sort_by { |map| map.values.flatten.size }
      expect(first_shard.keys).to eq(["Test Target3"])
      expect(first_shard.values).to eq([["Class3"]])

      expect(second_shard.keys.to_set).to eq(["Test Target1", "Test Target2"].to_set)
      expect(second_shard.values.to_set).to eq([["Class1"], ["Class2"]].to_set)
    end

    it "raises an error if there are too many shards" do
      too_many_machines = 2
      stream_parser = XCKnife::StreamParser.new(too_many_machines, [["Test Target1"]])
      partition = { "Test Target1" => { "Class1" => 1000 } }
      expect { stream_parser.compute_single_shards(too_many_machines, partition) }.
        to raise_error(XCKnife::XCKnifeError, "Too many shards")
    end
  end

  it "can compute test for all partitions" do
    stream_parser = XCKnife::StreamParser.new(3, [["TargetOnPartition1"], ["TargetOnPartition2"]])
    result = stream_parser.compute_shards_for_partitions([{ "TargetOnPartition1" => { "TestClass1" => 1000 } },
      { "TargetOnPartition2" => { "TestClass2" => 4000, "TestClass3" => 4000 } }])
    expect(result.test_maps).to eq([[{ "TargetOnPartition1" => ["TestClass1"] }],
      [{ "TargetOnPartition2" => ["TestClass2"] },
        { "TargetOnPartition2" => ["TestClass3"] }]])
    expect(result.test_times).to eq [[1000], [4000, 4000]]
    expect(result.total_test_time).to eq 9000
    expect(result.test_time_imbalances.to_h).to eq({
      partition_set: [0.4, 1.6],
      partitions: [[1.0], [1.0, 1.0]]
    })
  end

  it "can compute for only one partition set" do
    stream_parser = XCKnife::StreamParser.new(1, [["TargetOnPartition1"]])
    historical_events = [xctool_target_event("TargetOnPartition1"),
      xctool_test_event("ClassTest1", "test1"),
    ]
    result = stream_parser.compute_shards_for_events(historical_events)
    expect(result.test_maps).to eq([[{ "TargetOnPartition1" => ["ClassTest1"] }]])
    expect(result.test_times).to eq [[1000]]
    expect(result.total_test_time).to eq 1000
    expect(result.stats.to_h).to eq({historical_total_tests: 1, current_total_tests: 0, class_extrapolations: 0, target_extrapolations: 0})
    expect(result.test_time_imbalances.to_h).to eq({
      partition_set: [1.0],
      partitions: [[1.0]]
    })
  end

  def xctool_test_event(class_name, method_name, duration = 1.0)
    OpenStruct.new({ result: "success",
      exceptions: [],
      test: "-[#{class_name} #{method_name}]",
      className: class_name,
      event: "end-test",
      methodName: method_name,
      succeeded: true,
      output: "",
      totalDuration: duration,
      timestamp: 0
    })
  end

  def xctool_target_event(target_name)
    OpenStruct.new({ result: "success",
      event: "begin-ocunit",
      targetName: target_name
    })
  end
end
