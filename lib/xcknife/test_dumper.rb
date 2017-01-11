require 'json'
require 'pp'
require 'fileutils'
require 'tmpdir'
require 'ostruct'
require 'set'

module XCKnife
  class TestDumper
    def self.invoke
      new(ARGV).run
    end

    def initialize(args)
      @derived_data_folder, @output_file, @device_id = args
      @device_id ||= "booted"
    end

    def run
      if @derived_data_folder.nil? or @output_file.nil?
        return puts "Usage: xcknife-test-dumper [derived_data_folder] [output_file] [<device_id>]"
      end
      helper = TestDumperHelper.new(@device_id)
      output_fd = File.open(@output_file, "w")
      Dir.mktmpdir("xctestdumper_") do |outfolder|
        helper.call(@derived_data_folder, outfolder).each do |test_specification|
          concat_to_file(test_specification, output_fd)
        end
      end
      output_fd.close
      puts "Done listing test methods"
    end

    private
    def concat_to_file(test_specification, output_fd)
      file = test_specification.json_stream_file
      wait_test_dumper_completion(file)
        IO.readlines(file).each do |line|
        event = OpenStruct.new(JSON.load(line))
        output_fd.write(line) unless should_test_event_be_ignored?(test_specification, event)
      end
      output_fd.flush
    end

    # Current limitation: this only supports class level skipping
    def should_test_event_be_ignored?(test_specification, event)
      return false unless event["test"] == "1"
      test_specification.skip_test_identifiers.include?(event["className"])
    end

    def wait_test_dumper_completion(file)
      retries_count = 0
      until has_test_dumper_terminated?(file)  do
        retries_count += 1
        assert_has_not_timed_out(retries_count, file)
        sleep 0.1
      end
    end

    def assert_has_not_timed_out(retries_count, file)
      if retries_count == 100
        puts "Timeout error on: #{file}"
        exit 1
      end
    end

    def has_test_dumper_terminated?(file)
      return false unless File.exists?(file)
      last_line = `tail -n 1 "#{file}"`
      return /Completed Test Dumper/.match(last_line)
    end
  end


  class TestDumperHelper
    TestSpecification = Struct.new :json_stream_file, :skip_test_identifiers

    def initialize(device_id)
      @xcode_path = `xcode-select -p`.strip
      @simctl_path = `xcrun -f simctl`.strip
      @platforms_path = "#{@xcode_path}/Platforms/"
      @platform_path = "#{@platforms_path}/iPhoneSimulator.platform"
      @sdk_path = "#{@platform_path}/Developer/SDKs/iPhoneSimulator.sdk"
      @testroot = nil
      @device_id = device_id
    end

    def call(derived_data_folder, list_folder)
      @testroot = "#{derived_data_folder}/Build/Products/"
      xctestrun_file = Dir["#{@testroot}/*.xctestrun"].first
      if xctestrun_file.nil?
        puts "No xctestrun on #{@testroot}"
        exit 1
      end
      xctestrun_as_json = `plutil -convert json -o - "#{xctestrun_file}"`
      FileUtils.mkdir_p(list_folder)
      JSON.load(xctestrun_as_json).map do |test_bundle_name, test_bundle|
        list_tests_wiht_simctl(list_folder, test_bundle, test_bundle_name)
      end
    end

    def list_tests_wiht_simctl(list_folder, test_bundle, test_bundle_name)
      env_variables = test_bundle["EnvironmentVariables"]
      testing_env_variables = test_bundle["TestingEnvironmentVariables"]
      outpath = "#{list_folder}/#{test_bundle_name}"
      test_host = replace_vars(test_bundle["TestHostPath"])
      test_bundle_path = replace_vars(test_bundle["TestBundlePath"], test_host)
      test_dumper_path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'TestDumper', 'TestDumper.dylib'))
      unless File.exist?(test_dumper_path)
        warn "Could not find TestDumpber.dylib on #{test_dumper_path}"
        exit 1
      end

      is_logic_test = test_bundle["TestHostBundleIdentifier"].nil?
      env = simctl_child_attrs(
        "XCTEST_TYPE" => is_logic_test ? "LOGICTEST" : "APPTEST",
        "XCTEST_TARGET" => test_bundle_name,
        "TestDumperOutputPath" => outpath,
        "IDE_INJECTION_PATH" => testing_env_variables["DYLD_INSERT_LIBRARIES"],
        "XCInjectBundleInto" => testing_env_variables["XCInjectBundleInto"],
        "XCInjectBundle" => test_bundle_path,
        "TestBundleLocation" => test_bundle_path,
        "OS_ACTIVITY_MODE" => "disable",
        "DYLD_PRINT_LIBRARIES" => "YES",
        "DYLD_PRINT_ENV" => "YES",
        "DYLD_ROOT_PATH" => @sdk_path,
        "DYLD_LIBRARY_PATH" => env_variables["DYLD_LIBRARY_PATH"],
        "DYLD_FRAMEWORK_PATH" => env_variables["DYLD_FRAMEWORK_PATH"],
        "DYLD_FALLBACK_LIBRARY_PATH" => "#{@sdk_path}/usr/lib",
        "DYLD_FALLBACK_FRAMEWORK_PATH" => "#{@platform_path}/Developer/Library/Frameworks",
        "DYLD_INSERT_LIBRARIES" => test_dumper_path,
      )
      inject_vars(env, test_host)
      if is_logic_test
        run_logic_test(env, test_host, test_bundle_path)
      else
        install_app(test_host)
        test_host_bundle_identifier = replace_vars(test_bundle["TestHostBundleIdentifier"], test_host)
        run_apptest(env, test_host_bundle_identifier, test_bundle_path)
      end
      return TestSpecification.new outpath, discover_tests_to_skip(test_bundle)
    end

    private

    def discover_tests_to_skip(test_bundle)
      identifier_for_test_method = "/"
      skip_test_identifiers = test_bundle["SkipTestIdentifiers"] || []
      skip_test_identifiers.reject { |i| i.include?(identifier_for_test_method) }.to_set
    end

    def simctl
      @simctl_path
    end

    def replace_vars(str, testhost = "<UNKNOWN>")
      str.gsub("__PLATFORMS__", @platforms_path).
        gsub("__TESTHOST__", testhost).
        gsub("__TESTROOT__", @testroot)
    end

    def inject_vars(env, test_host)
      env.each do |k, v|
        env[k] = replace_vars(v || "", test_host)
      end
    end

    def simctl_child_attrs(attrs = {})
      env = {}
      attrs.each { |k, v| env["SIMCTL_CHILD_#{k}"] = v }
      env
    end

    def install_app(test_host_path)
      until system("#{simctl} install #{@device_id} '#{test_host_path}'")
        sleep 0.1
      end
    end

    def run_apptest(env, test_host_bundle_identifier, test_bundle_path)
      call_simctl env, "launch #{@device_id} '#{test_host_bundle_identifier}' -XCTest All '#{test_bundle_path}'"
    end

    def run_logic_test(env, test_host, test_bundle_path)
      call_simctl env, "spawn #{@device_id} '#{test_host}' -XCTest All '#{test_bundle_path}' 2> /dev/null"
    end

    def call_simctl(env, string_args)
      cmd = "#{simctl} #{string_args}"
      puts "Running:\n$ #{cmd}"
      unless system(env, cmd)
        puts "Simctl errored with the following env:\n #{env.pretty_print_inspect}"
      end
    end
  end
end
