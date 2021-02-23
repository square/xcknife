# frozen_string_literal: true

require 'spec_helper'
require 'set'

EXPECTED_OUTPUT = <<~DUMP_OUTPUT
  {"message":"Starting Test Dumper","event":"begin-test-suite","testType":"APPTEST"}
  {"event":"begin-ocunit","bundleName":"CommonTestTarget.xctest","targetName":"CommonTestTarget"}
  {"test":"1","className":"CommonTestClass","event":"end-test","totalDuration":"0"}
  {"message":"Completed Test Dumper","event":"end-action","testType":"APPTEST"}
  {"message":"Starting Test Dumper","event":"begin-test-suite","testType":"LOGICTEST"}
  {"event":"begin-ocunit","bundleName":"iPhoneTestTarget.xctest","targetName":"iPhoneTestTarget"}
  {"test":"1","className":"iPhoneTestClassAlpha","event":"end-test","totalDuration":"0"}
  {"test":"1","className":"iPhoneTestClassBeta","event":"end-test","totalDuration":"0"}
  {"test":"1","className":"iPhoneTestClassDelta","event":"end-test","totalDuration":"0"}
  {"test":"1","className":"iPhoneTestClassGama","event":"end-test","totalDuration":"0"}
  {"test":"1","className":"iPhoneTestClassOmega","event":"end-test","totalDuration":"0"}
  {"message":"Completed Test Dumper","event":"end-action","testType":"LOGICTEST"}
  {"message":"Starting Test Dumper","event":"begin-test-suite","testType":"LOGICTEST"}
  {"event":"begin-ocunit","bundleName":"SwiftTestTarget.xctest","targetName":"SwiftTestTarget"}
  {"test":"1","className":"ObjCTestClass","event":"end-test","totalDuration":"0"}
  {"test":"1","className":"SwiftTestTarget","event":"end-test","totalDuration":"0"}
  {"message":"Completed Test Dumper","event":"end-action","testType":"LOGICTEST"}
  {"message":"Starting Test Dumper","event":"begin-test-suite","testType":"APPTEST"}
  {"event":"begin-ocunit","bundleName":"iPadTestTarget.xctest","targetName":"iPadTestTarget"}
  {"test":"1","className":"iPadTestClassFour","event":"end-test","totalDuration":"0"}
  {"test":"1","className":"iPadTestClassOne","event":"end-test","totalDuration":"0"}
  {"test":"1","className":"iPadTestClassThree","event":"end-test","totalDuration":"0"}
  {"test":"1","className":"iPadTestClassTwo","event":"end-test","totalDuration":"0"}
  {"message":"Completed Test Dumper","event":"end-action","testType":"APPTEST"}
DUMP_OUTPUT

describe 'Test Dumper Acceptance', if: RUBY_PLATFORM.include?('darwin') do
  def sh(str)
    system(str)
  end

  def stop_all_simulators
    sh 'pkill -9 -f CoreSimulator'
    sh 'pkill -9 -f Xcode.app'
    sh 'pkill -9 xcodebuild'
    sh 'pkill -9 Simulator'
    sh 'pkill -9 launchd_sim'
  end

  def xcknife_exemplar_path
    target_dir = File.join(File.dirname(__FILE__), 'xcknife-exemplar')
    raise 'Please initialize with `git submodule update --recursive --init`' unless File.exist?(target_dir)

    target_dir
  end

  def test_xcknife_exemplar
    Dir.chdir(xcknife_exemplar_path) do
      sh './build.sh'
      sh './run-tests.sh'
    end
  end

  let(:simulator_uuid) do
    sim_name = "xcknife_test_dumper_#{Process.pid}"
    sim_type = 'com.apple.CoreSimulator.SimDeviceType.iPad-Air--3rd-generation-'
    sim_runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-13-6'
    `xcrun simctl create #{sim_name} #{sim_type} #{sim_runtime}`.strip
  end

  let(:derived_data_path) { File.join(xcknife_exemplar_path, 'derivedDataPath') }
  let(:outpath) { "#{__FILE__}.out.tmp" }
  let(:logger) { instance_spy(Logger) }

  before(:all) do
    stop_all_simulators
    test_xcknife_exemplar
  end

  before(:each) do
    FileUtils.rm_f outpath
    sh "xcrun simctl boot #{simulator_uuid}"
  end

  after(:each) do
    sh "xcrun simctl shutdown #{simulator_uuid}"
    sh "xcrun simctl delete #{simulator_uuid}"

    expect(File.read('/tmp/xcknife_testdumper_dylib.log').split("\n"))
      .to include('Starting TestDumper...')
      .and include('Listing all test bundles')
      .and include('test bundle loaded')
      .and include("Found a test bundle named: #{__dir__}/xcknife-exemplar/derivedDataPath/Build/Products/Debug-iphonesimulator/XCKnifeExemplar.app/PlugIns/iPadTestTarget.xctest")
      .and include('The test target is: iPadTestTarget of type APPTEST')
      .and include('EndingTestDumper...')
      .and include('Exiting with status 0')
  end

  it 'run test dumper on example project' do
    expect { XCKnife::TestDumper.new([derived_data_path, outpath, simulator_uuid], logger: logger).run }.not_to raise_error
    expect(IO.read(outpath).lines).to eq(EXPECTED_OUTPUT.lines)
  end

  it 'dumps tests using nm on example project' do
    test_bundle_names = %w[CommonTestTarget iPhoneTestTarget SwiftTestTarget]
    expect_any_instance_of(XCKnife::TestDumperHelper).to receive(:list_tests_with_nm).exactly(3).times.and_call_original
    expect_any_instance_of(XCKnife::TestDumperHelper).to receive(:list_tests_with_simctl).once.and_call_original
    expect { XCKnife::TestDumper.new([derived_data_path, outpath, simulator_uuid, '--naive-dump', test_bundle_names.join(',')], logger: logger).run }.not_to raise_error

    # Test dumper outputs tests enumerated by nm by threading, check for their presence rather than their exact order
    output_lines = IO.read(outpath).lines
    expect(output_lines.sort).to eq(EXPECTED_OUTPUT.lines.sort)
  end
end
