require 'json'
require 'pp'
require 'fileutils'
require 'tmpdir'
require 'ostruct'
require 'set'
require 'logger'

module XCKnife
  class TestDumper
    def self.invoke
      new(ARGV).run
    end

    attr_reader :logger

    def initialize(args)
      @debug = false
      @max_retry_count = 150
      @temporary_output_folder = nil
      @xcscheme_file = nil
      @parser = build_parser
      parse_arguments(args)
      @device_id ||= "booted"
      @logger = Logger.new($stdout)
      @logger.level = @debug ? Logger::DEBUG : Logger::FATAL
      @parser = nil
    end

    def run
      helper = TestDumperHelper.new(@device_id, @max_retry_count, @debug, @logger)
      extra_environment_variables = parse_scheme_file
      logger.info { "Environment variables from xcscheme: #{extra_environment_variables.pretty_inspect}" }
      output_fd = File.open(@output_file, "w")
      if @temporary_output_folder.nil?
        Dir.mktmpdir("xctestdumper_") do |outfolder|
          list_tests(extra_environment_variables, helper, outfolder, output_fd)
        end
      else
        unless File.directory?(@temporary_output_folder)
          puts "Error no such directory: #{@temporary_output_folder}"
          exit 1
        end

        if Dir.entries(@temporary_output_folder).any? { |f| File.file?(File.join(@temporary_output_folder,f)) }
          puts "Warning: #{@temporary_output_folder} is not empty! Files can be overwritten."
        end
        list_tests(extra_environment_variables, helper, @temporary_output_folder, output_fd)
      end
      output_fd.close
      puts "Done listing test methods"
    end

    private
    def list_tests(extra_environment_variables, helper, outfolder, output_fd)
      helper.call(@derived_data_folder, outfolder, extra_environment_variables).each do |test_specification|
        concat_to_file(test_specification, output_fd)
      end
    end


    def parse_scheme_file
      return {} unless @xcscheme_file
      unless File.exists?(@xcscheme_file)
        puts "Error: no such xcscheme file: #{@xcscheme_file}"
        exit 1
      end
      XCKnife::XcschemeAnalyzer.extract_environment_variables(IO.read(@xcscheme_file))
    end

    def parse_arguments(args)
      positional_arguments = parse_options(args)
      if positional_arguments.size < required_arguments.size
        warn_and_exit("You must specify *all* required arguments: #{required_arguments.join(", ")}")
      end
      @derived_data_folder, @output_file, @device_id = positional_arguments
    end

    def parse_options(args)
      begin
        return @parser.parse(args)
      rescue OptionParser::ParseError => error
        warn_and_exit(error)
      end
    end

    def build_parser
      OptionParser.new do |opts|
        opts.banner += " #{arguments_banner}"
        opts.on("-d", "--debug", "Debug mode enabled") { |v| @debug = v }
        opts.on("-r", "--retry-count COUNT", "Max retry count for simulator output", Integer) { |v| @max_retry_count = v }
        opts.on("-t", "--temporary-output OUTPUT_FOLDER", "Sets temporary Output folder") { |v| @temporary_output_folder = v }
        opts.on("-s", "--scheme XCSCHEME_FILE", "Reads environments variables from the xcscheme file") { |v| @xcscheme_file = v }

        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end
    end

    def required_arguments
      %w[derived_data_folder output_file]
    end

    def optional_arguments
      %w[device_id]
    end

    def arguments_banner
      optional_args = optional_arguments.map { |a| "[#{a}]" }
      (required_arguments + optional_args).join(" ")
    end

    def warn_and_exit(msg)
      warn "#{msg.to_s.capitalize} \n\n#{@parser}"
      exit 1
    end

    def concat_to_file(test_specification, output_fd)
      file = test_specification.json_stream_file
      IO.readlines(file).each do |line|
        event = OpenStruct.new(JSON.load(line))
        if should_test_event_be_ignored?(test_specification, event)
          logger.info "Skipped test dumper line #{line}"
        else
          output_fd.write(line)
        end
        output_fd.flush
      end
      output_fd.flush
    end

    # Current limitation: this only supports class level skipping
    def should_test_event_be_ignored?(test_specification, event)
      return false unless event["test"] == "1"
      test_specification.skip_test_identifiers.include?(event["className"])
    end
  end

  class TestDumperHelper
    TestSpecification = Struct.new :json_stream_file, :skip_test_identifiers

    attr_reader :logger

    def initialize(device_id, max_retry_count, debug, logger)
      @xcode_path = `xcode-select -p`.strip
      @simctl_path = `xcrun -f simctl`.strip
      @platforms_path = "#{@xcode_path}/Platforms/"
      @platform_path = "#{@platforms_path}/iPhoneSimulator.platform"
      @sdk_path = "#{@platform_path}/Developer/SDKs/iPhoneSimulator.sdk"
      @testroot = nil
      @device_id = device_id
      @max_retry_count = max_retry_count
      @logger = logger
      @debug = debug
    end

    def call(derived_data_folder, list_folder, extra_environment_variables = {})
      @testroot = "#{derived_data_folder}/Build/Products/"
      xctestrun_file = Dir["#{@testroot}/*.xctestrun"].first
      if xctestrun_file.nil?
        puts "No xctestrun on #{@testroot}"
        exit 1
      end
      xctestrun_as_json = `plutil -convert json -o - "#{xctestrun_file}"`
      FileUtils.mkdir_p(list_folder)
      JSON.load(xctestrun_as_json).map do |test_bundle_name, test_bundle|
        test_specification = list_tests_wiht_simctl(list_folder, test_bundle, test_bundle_name, extra_environment_variables)
        wait_test_dumper_completion(test_specification.json_stream_file)
        test_specification
      end
    end

    private
    def list_tests_wiht_simctl(list_folder, test_bundle, test_bundle_name, extra_environment_variables)
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
      env.merge!(simctl_child_attrs(extra_environment_variables))
      inject_vars(env, test_host)
      logger.info { "Temporary TestDumper file for #{test_bundle_name} is #{outpath}" }
      if is_logic_test
        run_logic_test(env, test_host, test_bundle_path)
      else
        install_app(test_host)
        test_host_bundle_identifier = replace_vars(test_bundle["TestHostBundleIdentifier"], test_host)
        run_apptest(env, test_host_bundle_identifier, test_bundle_path)
      end
      return TestSpecification.new outpath, discover_tests_to_skip(test_bundle)
    end

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

    def wait_test_dumper_completion(file)
      retries_count = 0
      until has_test_dumper_terminated?(file)  do
        retries_count += 1
        if retries_count == @max_retry_count
          puts "Timeout error on: #{file}"
          exit 1
        end
        sleep 0.1
      end
    end

    def has_test_dumper_terminated?(file)
      return false unless File.exists?(file)
      last_line = `tail -n 1 "#{file}"`
      return /Completed Test Dumper/.match(last_line)
    end

    def run_apptest(env, test_host_bundle_identifier, test_bundle_path)
      call_simctl env, "launch #{@device_id} '#{test_host_bundle_identifier}' -XCTest All '#{test_bundle_path}'"
    end

    def run_logic_test(env, test_host, test_bundle_path)
      call_simctl env, "spawn #{@device_id} '#{test_host}' -XCTest All '#{test_bundle_path}'#{redirect_output}"
    end

    def redirect_output
      return '' unless @debug
      ' 2> /dev/null'
    end

    def call_simctl(env, string_args)
      cmd = "#{simctl} #{string_args}"
      puts "Running:\n$ #{cmd}"
      logger.info { "Environment variables:\n #{env.pretty_print_inspect}" }
      unless system(env, cmd)
        puts "Simctl errored with the following env:\n #{env.pretty_print_inspect}"
      end
    end
  end
end
