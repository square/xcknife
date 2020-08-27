# frozen_string_literal: true

require 'xcknife/json_stream_parser_helper'
require 'json'
require 'set'
require 'ostruct'
require 'forwardable'

module XCKnife
  class StreamParser
    include JsonStreamParserHelper

    attr_reader :number_of_shards, :test_partitions, :stats, :relevant_partitions

    def initialize(number_of_shards, test_partitions, options_for_metapartition: Array.new(test_partitions.size, {}), allow_fewer_shards: false)
      @number_of_shards = number_of_shards
      @test_partitions = test_partitions.map(&:to_set)
      @relevant_partitions = test_partitions.flatten.to_set
      @stats = ResultStats.new
      @options_for_metapartition = options_for_metapartition.map { |o| Options::DEFAULT.merge(o) }
      @allow_fewer_shards = allow_fewer_shards
      ResultStats.members.each { |k| @stats[k] = 0 }
    end

    PartitionWithMachines = Struct.new :test_time_map, :number_of_shards, :partition_time, :max_shard_count, :options
    MachineAssignment = Struct.new :test_time_map, :total_time
    ResultStats = Struct.new :historical_total_tests, :current_total_tests, :class_extrapolations, :target_extrapolations
    Options = Struct.new :max_shard_count, :split_bundles_across_machines, :allow_fewer_shards do
      def merge(hash)
        self.class.new(*to_h.merge(hash).values_at(*members))
      end
    end
    Options::DEFAULT = Options.new(nil, true, false).freeze

    class PartitionResult
      TimeImbalances = Struct.new :partition_set, :partitions
      attr_reader :stats, :test_maps, :test_times, :total_test_time, :test_time_imbalances, :test_time_for_partitions

      extend Forwardable
      delegate ResultStats.members => :@stats

      def initialize(stats, partition_sets, test_time_for_partitions)
        @stats = stats
        @partition_sets = partition_sets
        @test_maps = partition_sets_map(&:test_time_map)
        @test_times = partition_sets_map(&:total_time)
        @total_test_time = test_times.flatten.inject(:+)
        @test_time_imbalances = compute_test_time_imbalances
        @test_time_for_partitions = test_time_for_partitions.inject(&:merge)
      end

      private

      # Yields the imbalances ratios of the partition sets, and the internal imbalance ratio of the respective partitions
      def compute_test_time_imbalances
        times = test_times
        average_partition_size = times.map { |l| l.inject(:+).to_f / l.size }
        ideal_partition_set_avg = average_partition_size.inject(:+) / @partition_sets.size
        partition_set_imbalance = average_partition_size.map { |avg| avg / ideal_partition_set_avg }

        internal_partition_imbalance = times.map do |partition_times|
          internal_total =  partition_times.inject(:+)
          partition_times.map do |partition_time|
            (partition_time * partition_times.size).to_f / internal_total
          end
        end
        TimeImbalances.new partition_set_imbalance, internal_partition_imbalance
      end

      def partition_sets_map(&block)
        @partition_sets.map { |assignemnt_list| assignemnt_list.map(&block) }
      end
    end

    # Parses the output of a xctool json-stream reporter and compute the shards based of that
    # see: https://github.com/facebook/xctool#included-reporters
    #
    # @param historical_filename: String  the path of the, usually historical, test time performance.
    # @param current_test_filename: [String, nil] = the path of the current test names and targets,
    def compute_shards_for_file(historical_filename, current_test_filename = nil)
      compute_shards_for_events(parse_json_stream_file(historical_filename), parse_json_stream_file(current_test_filename))
    end

    def compute_shards_for_events(historical_events, current_events = nil)
      compute_shards_for_partitions(test_time_for_partitions(historical_events, current_events))
    end

    def compute_shards_for_partitions(test_time_for_partitions)
      PartitionResult.new(@stats, split_machines_proportionally(test_time_for_partitions).map do |partition|
        compute_single_shards(partition.number_of_shards, partition.test_time_map, options: partition.options)
      end, test_time_for_partitions)
    end

    def test_time_for_partitions(historical_events, current_events = nil)
      analyzer = EventsAnalyzer.for(current_events, relevant_partitions)
      @stats[:current_total_tests] = analyzer.total_tests
      times_for_target_class = Hash.new { |h, current_target| h[current_target] = Hash.new(0) }
      each_test_event(historical_events) do |target_name, result|
        next unless relevant_partitions.include?(target_name)

        inc_stat :historical_total_tests
        next unless analyzer.test_class?(target_name, result.className)

        times_for_target_class[target_name][result.className] += (result.totalDuration * 1000).ceil
      end

      extrapolate_times_for_current_events(analyzer, times_for_target_class) if current_events
      hash_partitions(times_for_target_class)
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def split_machines_proportionally(partitions)
      total = 0
      partitions.each do |test_time_map|
        each_duration(test_time_map) { |duration_in_milliseconds| total += duration_in_milliseconds }
      end

      used_shards = 0
      assignable_shards = number_of_shards - partitions.size
      partition_with_machines_list = partitions.each_with_index.map do |test_time_map, metapartition|
        options = @options_for_metapartition[metapartition]
        partition_time = 0
        max_shard_count = test_time_map.each_value.map(&:size).reduce(&:+) || 1
        max_shard_count = [max_shard_count, options.max_shard_count].min if options.max_shard_count
        each_duration(test_time_map) { |duration_in_milliseconds| partition_time += duration_in_milliseconds }
        n = [1 + (assignable_shards * partition_time.to_f / total).floor, max_shard_count].min
        used_shards += n
        PartitionWithMachines.new(test_time_map, n, partition_time, max_shard_count, options)
      end

      fifo_with_machines_who_can_use_more_shards = partition_with_machines_list.select { |x| x.number_of_shards < x.max_shard_count }.sort_by(&:partition_time)
      while number_of_shards > used_shards
        if fifo_with_machines_who_can_use_more_shards.empty?
          break if @allow_fewer_shards

          raise XCKnife::XCKnifeError, "There are #{number_of_shards - used_shards} extra machines"
        end
        machine = fifo_with_machines_who_can_use_more_shards.pop
        machine.number_of_shards += 1
        used_shards += 1
        fifo_with_machines_who_can_use_more_shards.unshift(machine) if machine.number_of_shards < machine.max_shard_count
      end
      partition_with_machines_list
    end

    # Computes a 2-aproximation to the optimal partition_time, which is an instance of the Open shop scheduling problem (which is NP-hard)
    # see: https://en.wikipedia.org/wiki/Open-shop_scheduling
    def compute_single_shards(number_of_shards, test_time_map, options: Options::DEFAULT)
      raise XCKnife::XCKnifeError, 'There are not enough workers provided' if number_of_shards <= 0
      raise XCKnife::XCKnifeError, 'Cannot shard an empty partition_time' if test_time_map.empty?

      assignements = Array.new(number_of_shards) { MachineAssignment.new(Hash.new { |k, v| k[v] = [] }, 0) }

      list_of_test_target_class_times = []
      test_time_map.each do |test_target, class_times|
        class_times.each do |class_name, duration_in_milliseconds|
          list_of_test_target_class_times << [test_target, class_name, duration_in_milliseconds]
        end
      end

      # This might seem like an uncessary level of indirection, but it allows us to keep
      # logic consistent regardless of the `split_bundles_across_machines` option
      group = list_of_test_target_class_times.group_by do |test_target, class_name, _duration_in_milliseconds|
        options.split_bundles_across_machines ? [test_target, class_name] : test_target
      end

      list_of_test_target_classes_times = group.map do |(test_target, _), classes|
        [
          test_target,
          classes.map { |_test_target, class_name, _duration_in_milliseconds| class_name },
          classes.reduce(0) { |total_duration, (_test_target, _class_name, duration_in_milliseconds)| total_duration + duration_in_milliseconds }
        ]
      end

      list_of_test_target_classes_times.sort_by! { |_test_target, _class_names, duration_in_milliseconds| -duration_in_milliseconds }
      list_of_test_target_classes_times.each do |test_target, class_names, duration_in_milliseconds|
        assignemnt = assignements.min_by(&:total_time)
        assignemnt.test_time_map[test_target].concat class_names
        assignemnt.total_time += duration_in_milliseconds
      end

      if (empty_test_map_assignments = assignements.select { |a| a.test_time_map.empty? }) && !empty_test_map_assignments.empty? && !options.allow_fewer_shards
        test_grouping = options.split_bundles_across_machines ? 'classes' : 'targets'
        raise XCKnife::XCKnifeError, "Too many shards -- #{empty_test_map_assignments.size} of #{number_of_shards} assignments are empty," \
                                     " because there are not enough test #{test_grouping} for that many shards."
      end
      assignements.reject! { |a| a.test_time_map.empty? }

      assignements
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def parse_json_stream_file(filename)
      return nil if filename.nil?
      return [] unless File.exist?(filename)

      lines = IO.readlines(filename)
      lines.lazy.map { |line| OpenStruct.new(JSON.parse(line)) }
    end

    private

    def inc_stat(name)
      @stats[name] += 1
    end

    def each_duration(test_time_map)
      test_time_map.each do |_test_target, class_times|
        class_times.each do |_class_name, duration_in_milliseconds|
          yield(duration_in_milliseconds)
        end
      end
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def extrapolate_times_for_current_events(analyzer, times_for_target_class)
      median_map = {}
      times_for_target_class.each do |test_target, class_times|
        median_map[test_target] = median(class_times.values)
      end

      all_times_for_all_classes = times_for_target_class.values.flat_map(&:values)
      median_of_targets = median(all_times_for_all_classes)
      analyzer.target_class_map.each do |test_target, class_set|
        if times_for_target_class.key?(test_target)
          class_set.each do |clazz|
            unless times_for_target_class[test_target].key?(clazz)
              inc_stat :class_extrapolations
              times_for_target_class[test_target][clazz] = median_map[test_target]
            end
          end
        else
          inc_stat :target_extrapolations
          class_set.each do |clazz|
            inc_stat :class_extrapolations
            times_for_target_class[test_target][clazz] = extrapolated_duration(median_of_targets, class_set)
          end
        end
      end
    end

    DEFAULT_EXTRAPOLATED_DURATION = 1000
    def extrapolated_duration(median_of_targets, class_set)
      return DEFAULT_EXTRAPOLATED_DURATION if median_of_targets.nil?

      median_of_targets / class_set.size
    end

    def median(array)
      array.sort[array.size / 2]
    end

    def hash_partitions(times)
      ret = Array.new(test_partitions.size) { {} }
      times.each do |test_target, times_map|
        test_partitions.each_with_index do |partition, i|
          ret[i][test_target] = times_map if partition.include?(test_target)
        end
      end
      ret.each_with_index do |partition, index|
        raise XCKnife::XCKnifeError, "The following partition has no tests: #{test_partitions[index].to_a.inspect}" if partition.empty?
      end
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity
end
