require 'optparse'

module XCKnife
  class Runner
    include XCToolCmdHelper

    def self.invoke
      new(ARGV).run
    end

    attr_reader :parser

    def initialize(args)
      @abbreviated_output = false
      @xcodebuild_output = false
      @partitions = []
      @partition_names = []
      @worker_count = nil
      @historical_timings_file = nil
      @current_tests_file = nil
      @output_file_name = nil
      parse_arguments(args)
    end

    def run
      stream_parser = XCKnife::StreamParser.new(@worker_count, @partitions)
      result = stream_parser.compute_shards_for_file(@historical_timings_file, @current_tests_file)
      data = @abbreviated_output ? gen_abbreviated_output(result) : gen_full_output(result)
      write_output(data)
    rescue XCKnife::XCKnifeError => e
      warn "Error: #{e}"
      exit 1
    end

    private
    def gen_abbreviated_output(result)
      result.test_maps.map { |partition_set| only_arguments_for_a_partition_set(partition_set, output_type) }
    end


    def output_type
      @xcodebuild_output ? :xcodebuild : :xctool
    end

    def gen_full_output(result)
      {
        metadata: {
          worker_count: @worker_count,
          partition_set_count: result.test_maps.size,
          total_time_in_ms: result.total_test_time,
        }.merge(result.stats.to_h),
        partition_set_data: partition_sets_data(result)
      }
    end

    def partition_sets_data(result)
      shard_number = 0
      result.test_maps.each_with_index.map do |partition_set, partition_set_i|
        partition_data = partition_set.each_with_index.map do |partition, partition_j|
          shard_number += 1
          partition_data(result, shard_number, partition, partition_set_i, partition_j)
        end

        {
          partition_set: @partition_names[partition_set_i],
          size: partition_set.size,
          imbalance_ratio: result.test_time_imbalances.partition_set[partition_set_i],
          partitions: partition_data
        }
      end
    end

    def partition_data(result, shard_number, partition, partition_set_i, partition_j)
      {
        shard_number: shard_number,
        cli_arguments: only_arguments(output_type, partition),
        partition_imbalance_ratio: result.test_time_imbalances.partitions[partition_set_i][partition_j]
      }
    end

    def write_output(data)
      json = JSON.pretty_generate(data)
      return puts json if @output_file_name.nil?
      File.open(@output_file_name, "w") { |f| f.puts(json) }
      puts "Wrote file to: #{@output_file_name}"
    end

    def parse_arguments(args)
      positional_arguments = parse_options(args)
      if positional_arguments.size < required_arguments.size
        warn_and_exit("You must specify *all* required arguments: #{required_arguments.join(", ")}")
      end
      if @partitions.empty?
        warn_and_exit("At least one target partition set must be provided with -p flag")
      end
      worker_count, @historical_timings_file, @current_tests_file = positional_arguments
      @worker_count = Integer(worker_count)
    end

    def parse_options(args)
      build_parser
      begin
        parser.parse(args)
      rescue OptionParser::ParseError => error
        warn_and_exit(error)
      end
    end

    def build_parser
      @parser = OptionParser.new do |opts|
        opts.banner += " #{arguments_banner}"
        opts.on("-p", "--partition TARGETS",
          "Comma separated list of targets. Can be used multiple times.") do |v|
          @partition_names << v
          @partitions << v.split(",")
        end
        opts.on("-o", "--output FILENAME", "Output file. Defaults to STDOUT") { |v| @output_file_name = v }
        opts.on("-a", "--abbrev", "Results are abbreviated") { |v| @abbreviated_output = v }
        opts.on("-x", "--xcodebuild-output", "Output is formatted for xcodebuild") { |v| @xcodebuild_output = v }

        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end
    end

    def required_arguments
      %w[worker-count historical-timings-json-stream-file]
    end

    def optional_arguments
      %w[current-tests-json-stream-file]
    end

    def arguments_banner
      optional_args = optional_arguments.map { |a| "[#{a}]" }
      (required_arguments + optional_args).join(" ")
    end

    def warn_and_exit(msg)
      warn "#{msg.to_s.capitalize} \n\n#{parser}"
      exit 1
    end
  end
end
