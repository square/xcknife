require 'json'
require 'pp'
require 'fileutils'
require 'tmpdir'
require 'ostruct'
require 'set'
require 'logger'
require 'shellwords'
require 'open3'
require 'xcknife/exceptions'
require 'etc'

module XCKnife
  class TestDumper
    def self.invoke
      new(ARGV).run
    end

    attr_reader :logger

    def initialize(args, logger: Logger.new($stdout, progname: 'xcknife test dumper'))
      @debug = false
      @max_retry_count = 150
      @temporary_output_folder = nil
      @xcscheme_file = nil
      @parser = build_parser
      @naive_dump_bundle_names = []
      @skip_dump_bundle_names = []
      @simctl_timeout = 0
      parse_arguments(args)
      @device_id ||= 'booted'
      @logger = logger
      @logger.level = @debug ? Logger::DEBUG : Logger::FATAL
      @parser = nil
    end

    def run
      helper = TestDumperHelper.new(@device_id, @max_retry_count, @debug, @logger, @dylib_logfile_path,
                                    naive_dump_bundle_names: @naive_dump_bundle_names, skip_dump_bundle_names: @skip_dump_bundle_names, simctl_timeout: @simctl_timeout)
      extra_environment_variables = parse_scheme_file
      logger.info { "Environment variables from xcscheme: #{extra_environment_variables.pretty_inspect}" }
      output_fd = File.open(@output_file, 'w')
      if @temporary_output_folder.nil?
        Dir.mktmpdir('xctestdumper_') do |outfolder|
          list_tests(extra_environment_variables, helper, outfolder, output_fd)
        end
      else
        unless File.directory?(@temporary_output_folder)
          raise TestDumpError, "Error no such directory: #{@temporary_output_folder}"
        end

        if Dir.entries(@temporary_output_folder).any? { |f| File.file?(File.join(@temporary_output_folder, f)) }
          puts "Warning: #{@temporary_output_folder} is not empty! Files can be overwritten."
        end
        list_tests(extra_environment_variables, helper, File.absolute_path(@temporary_output_folder), output_fd)
      end
      output_fd.close
      puts 'Done listing test methods'
    end

    private

    def list_tests(extra_environment_variables, helper, outfolder, output_fd)
      helper.call(@derived_data_folder, outfolder, extra_environment_variables).each do |test_specification|
        concat_to_file(test_specification, output_fd)
      end
    end

    def parse_scheme_file
      return {} unless @xcscheme_file
      raise ArgumentError, "Error: no such xcscheme file: #{@xcscheme_file}" unless File.exist?(@xcscheme_file)

      XCKnife::XcschemeAnalyzer.extract_environment_variables(IO.read(@xcscheme_file))
    end

    def parse_arguments(args)
      positional_arguments = parse_options(args)
      if positional_arguments.size < required_arguments.size
        warn_and_exit("You must specify *all* required arguments: #{required_arguments.join(', ')}")
      end
      @derived_data_folder, @output_file, @device_id = positional_arguments
    end

    def parse_options(args)
      @parser.parse(args)
    rescue OptionParser::ParseError => e
      warn_and_exit(e)
    end

    def build_parser
      OptionParser.new do |opts|
        opts.banner += " #{arguments_banner}"
        opts.on('-d', '--debug', 'Debug mode enabled') { |v| @debug = v }
        opts.on('-r', '--retry-count COUNT', 'Max retry count for simulator output', Integer) { |v| @max_retry_count = v }
        opts.on('-x', '--simctl-timeout SECONDS', 'Max allowed time in seconds for simctl commands', Integer) { |v| @simctl_timeout = v }
        opts.on('-t', '--temporary-output OUTPUT_FOLDER', 'Sets temporary Output folder') { |v| @temporary_output_folder = v }
        opts.on('-s', '--scheme XCSCHEME_FILE', 'Reads environments variables from the xcscheme file') { |v| @xcscheme_file = v }
        opts.on('-l', '--dylib_logfile DYLIB_LOG_FILE', 'Path for dylib log file') { |v| @dylib_logfile_path = v }
        opts.on('--naive-dump TEST_BUNDLE_NAMES', 'List of test bundles to dump using static analysis', Array) { |v| @naive_dump_bundle_names = v }
        opts.on('--skip-dump TEST_BUNDLE_NAMES', 'List of test bundles to skip dumping', Array) { |v| @skip_dump_bundle_names = v }

        opts.on_tail('-h', '--help', 'Show this message') do
          puts opts
          exit
        end
      end
    end

    def required_arguments
      %w[derived_data_folder output_file]
    end

    def optional_arguments
      %w[device_id simctl_timeout]
    end

    def arguments_banner
      optional_args = optional_arguments.map { |a| "[#{a}]" }
      (required_arguments + optional_args).join(' ')
    end

    def warn_and_exit(msg)
      raise TestDumpError, "#{msg.to_s.capitalize} \n\n#{@parser}"
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
      return false unless event['test'] == '1'

      test_specification.skip_test_identifiers.include?(event['className'])
    end
  end

  class TestDumperHelper
    TestSpecification = Struct.new :json_stream_file, :skip_test_identifiers

    attr_reader :logger

    def initialize(device_id, max_retry_count, debug, logger, dylib_logfile_path,
                   naive_dump_bundle_names: [], skip_dump_bundle_names: [], simctl_timeout: 0)
      @xcode_path = `xcode-select -p`.strip
      @simctl_path = `xcrun -f simctl`.strip
      @nm_path = `xcrun -f nm`.strip
      @swift_path = `xcrun -f swift`.strip
      @platforms_path = File.join(@xcode_path, 'Platforms')
      @platform_path = File.join(@platforms_path, 'iPhoneSimulator.platform')
      @sdk_path = File.join(@platform_path, 'Developer/SDKs/iPhoneSimulator.sdk')
      @testroot = nil
      @device_id = device_id
      @max_retry_count = max_retry_count
      @simctl_timeout = simctl_timeout
      @logger = logger
      @debug = debug
      @dylib_logfile_path = dylib_logfile_path if dylib_logfile_path
      @naive_dump_bundle_names = naive_dump_bundle_names
      @skip_dump_bundle_names = skip_dump_bundle_names
    end

    def call(derived_data_folder, list_folder, extra_environment_variables = {})
      @testroot = File.join(derived_data_folder, 'Build', 'Products')
      xctestrun_file = Dir[File.join(@testroot, '*.xctestrun')].first
      raise ArgumentError, "No xctestrun on #{@testroot}" if xctestrun_file.nil?

      xctestrun_as_json = `plutil -convert json -o - "#{xctestrun_file}"`
      FileUtils.mkdir_p(list_folder)
      list_tests(JSON.load(xctestrun_as_json), list_folder, extra_environment_variables)
    end

    private

    attr_reader :testroot

    def test_groups(xctestrun)
      xctestrun.group_by do |test_bundle_name, _test_bundle|
        if @skip_dump_bundle_names.include?(test_bundle_name)
          'single'
        elsif @naive_dump_bundle_names.include?(test_bundle_name)
          'nm'
        else
          'simctl'
        end
      end
    end

    # This executes naive test dumping in parallel by queueing up items onto a work queue to process
    # with 1 new thread per processor. Results are placed onto a threadsafe spec queue to avoid writing
    # to an object between threads, then popped off re-inserting them to our list of test results.
    def list_tests(xctestrun, list_folder, extra_environment_variables)
      xctestrun.reject! { |test_bundle_name, _| test_bundle_name == '__xctestrun_metadata__' }

      test_runs_by_method = test_groups(xctestrun)
      spec_queue = Queue.new
      nm_bundle_queue = Queue.new
      results = []
      single_tests = test_runs_by_method['single'] || []
      nm_tests = test_runs_by_method['nm'] || []
      simctl_tests = test_runs_by_method['simctl'] || []

      single_tests.each do |test_bundle_name, test_bundle|
        logger.info { "Skipping dumping tests in `#{test_bundle_name}` -- writing out fake event" }
        spec_queue << list_single_test(list_folder, test_bundle, test_bundle_name)
      end

      simctl_tests.each do |test_bundle_name, test_bundle|
        test_spec = list_tests_with_simctl(list_folder, test_bundle, test_bundle_name, extra_environment_variables)
        wait_test_dumper_completion(test_spec.json_stream_file)

        spec_queue << test_spec
      end

      nm_tests.each { |item| nm_bundle_queue << item }

      [Etc.nprocessors, nm_bundle_queue.size].min.times.map do
        nm_bundle_queue << :stop

        Thread.new do
          Thread.current.abort_on_exception = true

          until (item = nm_bundle_queue.pop) == :stop
            test_bundle_name, test_bundle = item
            spec_queue << list_tests_with_nm(list_folder, test_bundle, test_bundle_name)
          end
        end
      end.each(&:join)

      results << spec_queue.pop until spec_queue.empty?

      results
    end

    def list_tests_with_simctl(list_folder, test_bundle, test_bundle_name, extra_environment_variables)
      env_variables = test_bundle['EnvironmentVariables']
      testing_env_variables = test_bundle['TestingEnvironmentVariables']
      outpath = File.join(list_folder, test_bundle_name)
      test_host = replace_vars(test_bundle['TestHostPath'])
      test_bundle_path = replace_vars(test_bundle['TestBundlePath'], test_host)
      test_dumper_path = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'TestDumper', 'TestDumper.dylib'))
      raise TestDumpError, "Could not find TestDumper.dylib on #{test_dumper_path}" unless File.exist?(test_dumper_path)

      is_logic_test = test_bundle['TestHostBundleIdentifier'].nil?
      env = simctl_child_attrs(
        'XCTEST_TYPE' => xctest_type(test_bundle),
        'XCTEST_TARGET' => test_bundle_name,
        'TestDumperOutputPath' => outpath,
        'IDE_INJECTION_PATH' => testing_env_variables['DYLD_INSERT_LIBRARIES'],
        'XCInjectBundleInto' => testing_env_variables['XCInjectBundleInto'],
        'XCInjectBundle' => test_bundle_path,
        'TestBundleLocation' => test_bundle_path,
        'OS_ACTIVITY_MODE' => 'disable',
        'DYLD_PRINT_LIBRARIES' => 'YES',
        'DYLD_PRINT_ENV' => 'YES',
        'DYLD_ROOT_PATH' => @sdk_path,
        'DYLD_LIBRARY_PATH' => env_variables['DYLD_LIBRARY_PATH'],
        'DYLD_FRAMEWORK_PATH' => env_variables['DYLD_FRAMEWORK_PATH'],
        'DYLD_FALLBACK_LIBRARY_PATH' => "#{@sdk_path}/usr/lib",
        'DYLD_FALLBACK_FRAMEWORK_PATH' => "#{@platform_path}/Developer/Library/Frameworks",
        'DYLD_INSERT_LIBRARIES' => test_dumper_path
      )
      env.merge!(simctl_child_attrs(extra_environment_variables))
      inject_vars(env, test_host)
      FileUtils.rm_f(outpath)
      logger.info { "Temporary TestDumper file for #{test_bundle_name} is #{outpath}" }
      if is_logic_test
        run_logic_test(env, test_host, test_bundle_path)
      else
        install_app(test_host)
        test_host_bundle_identifier = replace_vars(test_bundle['TestHostBundleIdentifier'], test_host)
        run_apptest(env, test_host_bundle_identifier, test_bundle_path)
      end
      TestSpecification.new outpath, discover_tests_to_skip(test_bundle)
    end

    # Improvement?: assume that everything in the historical info is correct, so dont simctl or nm, and just spit out exactly what it said the classes were

    def list_tests_with_nm(list_folder, test_bundle, test_bundle_name)
      output_methods(list_folder, test_bundle, test_bundle_name) do |test_bundle_path|
        methods = []
        swift_demangled_nm(test_bundle_path) do |output|
          output.each_line do |line|
            next unless method = method_from_nm_line(line)

            methods << method
          end
        end
        methods
      end
    end

    def list_single_test(list_folder, test_bundle, test_bundle_name)
      output_methods(list_folder, test_bundle, test_bundle_name) do
        [{ class: test_bundle_name, method: 'test' }]
      end
    end

    def output_methods(list_folder, test_bundle, test_bundle_name)
      outpath = File.join(list_folder, test_bundle_name)
      logger.info { "Writing out TestDumper file for #{test_bundle_name} to #{outpath}" }
      test_specification = TestSpecification.new outpath, discover_tests_to_skip(test_bundle)

      test_bundle_path = replace_vars(test_bundle['TestBundlePath'], replace_vars(test_bundle['TestHostPath']))
      methods = yield(test_bundle_path)

      test_type = xctest_type(test_bundle)
      File.open test_specification.json_stream_file, 'a' do |f|
        f << JSON.dump(message: 'Starting Test Dumper', event: 'begin-test-suite', testType: test_type) << "\n"
        f << JSON.dump(event: 'begin-ocunit', bundleName: File.basename(test_bundle_path), targetName: test_bundle_name) << "\n"
        methods.map { |method| method[:class] }.uniq.each do |class_name|
          f << JSON.dump(test: '1', className: class_name, event: 'end-test', totalDuration: '0') << "\n"
        end
        f << JSON.dump(message: 'Completed Test Dumper', event: 'end-action', testType: test_type) << "\n"
      end

      test_specification
    end

    def discover_tests_to_skip(test_bundle)
      identifier_for_test_method = '/'
      skip_test_identifiers = test_bundle['SkipTestIdentifiers'] || []
      skip_test_identifiers.reject { |i| i.include?(identifier_for_test_method) }.to_set
    end

    def simctl
      @simctl_path
    end

    def wrapped_simctl(args)
      args = [*gtimeout, simctl] + args
      args
    end

    def gtimeout
      return [] unless @simctl_timeout > 0

      path = gtimeout_path
      if path.empty?
        puts "warning: simctl_timeout specified but 'gtimeout' is not installed. The specified timeout will be ignored."
        return []
      end

      [path, '-k', '5', @simctl_timeout.to_s]
    end

    def gtimeout_path
      `which gtimeout`.strip
    end

    def replace_vars(str, testhost = '<UNKNOWN>')
      str.gsub('__PLATFORMS__', @platforms_path)
         .gsub('__TESTHOST__', testhost)
         .gsub('__TESTROOT__', testroot)
    end

    def inject_vars(env, test_host)
      env.each do |k, v|
        env[k] = replace_vars(v || '', test_host)
      end
    end

    def simctl_child_attrs(attrs = {})
      env = {}
      attrs.each { |k, v| env["SIMCTL_CHILD_#{k}"] = v }
      env
    end

    def install_app(test_host_path)
      retries_count = 0
      max_retry_count = 3
      until (retries_count > max_retry_count) || call_simctl(['install', @device_id, test_host_path])
        retries_count += 1
        call_simctl ['shutdown', @device_id]
        call_simctl ['boot', @device_id]
        sleep 1.0
      end

      raise TestDumpError, "Installing #{test_host_path} failed" if retries_count > max_retry_count
    end

    def wait_test_dumper_completion(file)
      retries_count = 0
      until has_test_dumper_terminated?(file)
        retries_count += 1
        raise TestDumpError, "Timeout error on: #{file}" if retries_count == @max_retry_count

        sleep 0.1
      end
    end

    def has_test_dumper_terminated?(file)
      return false unless File.exist?(file)

      last_line = `tail -n 1 "#{file}"`
      last_line.include?('Completed Test Dumper')
    end

    def run_apptest(env, test_host_bundle_identifier, test_bundle_path)
      unless call_simctl(['launch', @device_id, test_host_bundle_identifier, '-XCTest', 'All', dylib_logfile_path, test_bundle_path], env: env)
        raise TestDumpError, "Launching #{test_bundle_path} in #{test_host_bundle_identifier} failed"
      end
    end

    def run_logic_test(env, test_host, test_bundle_path)
      opts = @debug ? {} : { err: '/dev/null' }
      unless call_simctl(['spawn', @device_id, test_host, '-XCTest', 'All', dylib_logfile_path, test_bundle_path], env: env, **opts)
        raise TestDumpError, "Spawning #{test_bundle_path} in #{test_host} failed"
      end
    end

    def call_simctl(args, env: {}, **spawn_opts)
      args = wrapped_simctl(args)
      cmd = Shellwords.shelljoin(args)
      puts "Running:\n$ #{cmd}"
      logger.info { "Environment variables:\n #{env.pretty_print_inspect}" }

      ret = system(env, *args, **spawn_opts)
      puts "Simctl errored with the following env:\n #{env.pretty_print_inspect}" unless ret
      ret
    end

    def dylib_logfile_path
      @dylib_logfile_path ||= '/tmp/xcknife_testdumper_dylib.log'
    end

    def xctest_type(test_bundle)
      if test_bundle['TestHostBundleIdentifier'].nil?
        'LOGICTEST'
      else
        'APPTEST'
      end
    end

    def swift_demangled_nm(test_bundle_path)
      Open3.pipeline_r([@nm_path, File.join(test_bundle_path, File.basename(test_bundle_path, '.xctest'))], [@swift_path, 'demangle']) do |o, _ts|
        yield(o)
      end
    end

    def method_from_nm_line(line)
      return unless line.strip =~ /^
        [\da-f]+\s # address
        [tT]\s # symbol type
        (?: # method
          -\[(.+)\s(test.+)\] # objc instance method
          | # or swift instance method
            _? # only present on Xcode 10.0 and below
            (?:@objc\s)? # optional objc annotation
            (?:[^\.]+\.)? # module name
            (.+) # class name
            \.(test.+)\s->\s\(\) # method signature
        )
      $/ox

      { class: Regexp.last_match(1) || Regexp.last_match(3), method: Regexp.last_match(2) || Regexp.last_match(4) }
    end
  end
end
