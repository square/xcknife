require 'spec_helper'
require 'set'

EXPECTED_OUTPUT = <<eof
{"message":"Starting Test Dumper","event":"begin-test-suite","testType":"LOGICTEST"}
{"event":"begin-ocunit","bundleName":"iPhoneTestTarget.xctest","targetName":"iPhoneTestTarget"}
{"test":"1","className":"iPhoneTestClassAlpha","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPhoneTestClassBeta","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPhoneTestClassDelta","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPhoneTestClassGama","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPhoneTestClassOmega","event":"end-test","totalDuration":"0"}
{"message":"Completed Test Dumper","event":"end-action","testType":"LOGICTEST"}
{"message":"Starting Test Dumper","event":"begin-test-suite","testType":"APPTEST"}
{"event":"begin-ocunit","bundleName":"CommonTestTarget.xctest","targetName":"CommonTestTarget"}
{"test":"1","className":"CommonTestClass","event":"end-test","totalDuration":"0"}
{"message":"Completed Test Dumper","event":"end-action","testType":"APPTEST"}
{"message":"Starting Test Dumper","event":"begin-test-suite","testType":"APPTEST"}
{"event":"begin-ocunit","bundleName":"iPadTestTarget.xctest","targetName":"iPadTestTarget"}
{"test":"1","className":"iPadTestClassFour","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPadTestClassOne","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPadTestClassThree","event":"end-test","totalDuration":"0"}
{"test":"1","className":"iPadTestClassTwo","event":"end-test","totalDuration":"0"}
{"message":"Completed Test Dumper","event":"end-action","testType":"APPTEST"}
eof

describe "Test Dumper Acceptance" do
  def sh(str)
    system(str)
  end

  def stop_all_simulators
    sh "pkill -9 -f CoreSimulator"
    sh "pkill -9 -f Xcode.app"
    sh "pkill -9 xcodebuild"
    sh "pkill -9 Simulator"
    sh "pkill -9 launchd_sim"
  end

  def xcknife_exemplar_path
    target_dir = File.join(File.dirname(__FILE__), "xcknife-exemplar")
    raise "Please initialize with `git submodule update --recursive --init`" unless File.exists?(target_dir)
    target_dir
  end

  def test_xcknife_exemplar
    Dir.chdir(xcknife_exemplar_path) do
      sh './build.sh'
      sh './run-tests.sh'
    end
  end

  if !/darwin/.match(RUBY_PLATFORM)
    xit "needs mac os as we are launching IOS simulators"
  else
    it "run test dumper on example project" do
      stop_all_simulators
      test_xcknife_exemplar
      derived_data = File.join(xcknife_exemplar_path, "derivedDataPath")
      outpath = "#{__FILE__}.out.tmp"
      File.unlink(outpath) if File.exists?(outpath)
      expect { XCKnife::TestDumper.new([derived_data, outpath]).run }.not_to raise_error
      expect(IO.read(outpath).lines.to_set).to eq(EXPECTED_OUTPUT.lines.to_set)
    end
  end
end
