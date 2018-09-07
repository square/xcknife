require 'spec_helper'

describe XCKnife::TestDumper do
  let(:args) {}
  let(:logger) { instance_double(Logger) }
  subject(:test_dumper) { described_class.new(args, logger: logger) }

  context 'argument parsing' do
  end
end

describe XCKnife::TestDumperHelper do
  let(:device_id) { 'device_id' }
  let(:max_retry_count) { 2 }
  let(:debug) { true }
  let(:logger) { instance_spy(Logger) }
  let(:dylib_logfile_path) { 'dylib_logfile_path' }
  let(:naive_dump_bundle_names) { ['NaiveBundle'] }
  let(:skip_dump_bundle_names) { ['SkipBundle'] }

  subject(:test_dumper_helper) do
    described_class.new(device_id, max_retry_count, debug, logger, dylib_logfile_path,
                        naive_dump_bundle_names: naive_dump_bundle_names, skip_dump_bundle_names: skip_dump_bundle_names)
  end

  describe '#list_tests' do
    it 'uses naive_dump_bundle_names to determine how to list tests' do
      xctestrun = {
        'NaiveBundle' => :test_bundle_naive,
        'OtherBundle' => :test_bundle_other,
      }
      list_folder = 'list_folder'
      extra_environment_variables = {}

      expect(test_dumper_helper).to receive(:list_tests_with_nm).once
        .with(list_folder, :test_bundle_naive, 'NaiveBundle')
        .and_return(naive_test_specification = XCKnife::TestDumperHelper::TestSpecification.new('naive/json_stream_file'))
      expect(test_dumper_helper).to receive(:list_tests_with_simctl).once
        .with(list_folder, :test_bundle_other, 'OtherBundle', extra_environment_variables)
        .and_return(other_test_specification = XCKnife::TestDumperHelper::TestSpecification.new('other/json_stream_file'))
      expect(test_dumper_helper).to receive(:wait_test_dumper_completion).with(other_test_specification.json_stream_file)

      expect(test_dumper_helper.send(:list_tests, xctestrun, list_folder, extra_environment_variables)).
        to eq [naive_test_specification, other_test_specification]
    end

    it 'skips dumping given bundles' do
      xctestrun = {
        'SkipBundle' => :test_bundle_skip,
        'OtherBundle' => :test_bundle_other,
      }
      list_folder = 'list_folder'
      extra_environment_variables = {}

      expect(test_dumper_helper).to receive(:list_tests_with_nm).never
      expect(test_dumper_helper).to receive(:list_tests_with_simctl).once
        .with(list_folder, :test_bundle_other, 'OtherBundle', extra_environment_variables)
        .and_return(other_test_specification = XCKnife::TestDumperHelper::TestSpecification.new('other/json_stream_file'))
      expect(test_dumper_helper).to receive(:list_single_test).once
        .with(list_folder, :test_bundle_skip, 'SkipBundle')
        .and_return(skip_test_specification = XCKnife::TestDumperHelper::TestSpecification.new('skip/json_stream_file'))
      expect(test_dumper_helper).to receive(:wait_test_dumper_completion).with(other_test_specification.json_stream_file)

      expect(test_dumper_helper.send(:list_tests, xctestrun, list_folder, extra_environment_variables)).
        to eq [skip_test_specification, other_test_specification]
    end
  end

  describe '#list_tests_with_nm' do
    let(:testroot) { 'testroot' }

    let(:list_folder) { Dir.mktmpdir }
    after { FileUtils.remove_entry list_folder }
    let(:json_stream_file) { File.join(list_folder, test_bundle_name) }

    let(:test_bundle) do
      {
        'TestBundlePath' => 'test_bundle_path.xctest',
        'TestHostPath' => 'test_host_path',
      }
    end
    let(:test_bundle_name) { 'test_bundle_name' }

    before { allow(test_dumper_helper).to receive(:testroot).and_return(testroot) }

    it "uses nm to find test classes" do
      expect(test_dumper_helper).to receive(:swift_demangled_nm)
        .with('test_bundle_path.xctest')
        .and_yield <<-OTOOL
0000000000001c10 t -[iPhoneTestClassAlpha testAres]
0000000000002d50 t -[iPhoneTestClassBeta testArtemis]
0000000000001650 t -[iPhoneTestClassDelta testApollo]
00000000000021d0 t -[iPhoneTestClassGama testPoseidon]
0000000000002790 t -[iPhoneTestClassOmega testZeus]
0000000000003950 s GCC_except_table0
                  U _OBJC_CLASS_$_NSString
0000000000004598 S _OBJC_CLASS_$_iPhoneTestClassAlpha
0000000000004570 S _OBJC_METACLASS_$_iPhoneTestClassAlpha
00000000000016d0 t -[CommonTestClass testCommonOne]
0000000000002250 t -[CommonTestClass testCommonThree]
0000000000001c90 t -[CommonTestClass testCommonTwo]
00000000000028d0 s GCC_except_table0
0000000000002a30 s GCC_except_table1
0000000000002b90 s GCC_except_table2
0000000000003258 S _OBJC_CLASS_$_CommonTestClass
000000000c003258 t -[iPhoneTestClassOmega helperTestThing]
000000000d003258 t +[iPhoneTestClassOmega helperTestThing]
000000000d003258 t +[iPhoneTestClassZeta helperTestThing]
00000000000017b0 T _SwiftTestTarget.SwiftTestClass.testExample() -> ()
00000000000017c0 t _@objc SwiftTestTarget.SwiftTestClass.testExample() -> ()
0000000000001a70 T _SwiftTestTarget.ABC.foo() -> Swift.String
        OTOOL

      test_specification = test_dumper_helper.send(:list_tests_with_nm, list_folder, test_bundle, test_bundle_name)
      expect(test_specification).to eq XCKnife::TestDumperHelper::TestSpecification.new(json_stream_file, Set.new)
      expect(File.read(json_stream_file)).to eq <<-JSONSTREAM
{"message":"Starting Test Dumper","event":"begin-test-suite","testType":"LOGICTEST"}
{"event":"begin-ocunit","bundleName":"test_bundle_path.xctest","targetName":"test_bundle_name"}
{"test":"1","className":"iPhoneTestClassAlpha","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPhoneTestClassBeta","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPhoneTestClassDelta","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPhoneTestClassGama","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPhoneTestClassOmega","event":"end-test","totalDuration":"0"}
{"test":"1","className":"CommonTestClass","event":"end-test","totalDuration":"0"}
{"test":"1","className":"SwiftTestClass","event":"end-test","totalDuration":"0"}
{"message":"Completed Test Dumper","event":"end-action","testType":"LOGICTEST"}
      JSONSTREAM
    end
  end
end
