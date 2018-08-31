require 'set'

module XCKnife
  module XCToolCmdHelper
    def only_arguments_for_a_partition_set(output_type, partition_set)
      method = "#{output_type}_only_arguments_for_a_partition_set"
      raise "Unknown output_type: #{output_type}" unless respond_to?(method)
      __send__(method, partition_set)
    end

    def only_arguments(output_type, partition)
      method = "#{output_type}_only_arguments"
      raise "Unknown output_type: #{output_type}" unless respond_to?(method)
      __send__(method, partition)
    end

    def xctool_only_arguments(single_partition)
      single_partition.flat_map do |test_target, classes|
        ['-only', "#{test_target}:#{classes.sort.join(',')}"]
      end
    end

    def xctool_only_arguments_for_a_partition_set(partition_set)
      partition_set.map { |partition| xctool_only_arguments(partition) }
    end

    # only-testing is available since Xcode 8
    def xcodebuild_only_arguments(single_partition, meta_partition = nil)
      only_targets = if meta_partition
        single_partition.keys.to_set & meta_partition.flat_map(&:keys).group_by(&:to_s).select{|_,v| v.size == 1 }.map(&:first).to_set
      else
        Set.new
      end

      only_target_arguments = only_targets.sort.map { |test_target| "-only-testing:#{test_target}" }

      only_class_arguments = single_partition.flat_map do |test_target, classes|
        next [] if only_targets.include?(test_target)

        classes.sort.map do |clazz|
          "-only-testing:#{test_target}/#{clazz}"
        end
      end.sort

      only_target_arguments + only_class_arguments
    end

    # skip-testing is available since Xcode 8
    def xcodebuild_skip_arguments(single_partition, test_time_for_partitions)
      excluded_targets = test_time_for_partitions.keys.to_set - single_partition.keys.to_set
      skipped_target_arguments = excluded_targets.sort.map { |test_target| "-skip-testing:#{test_target}" }

      skipped_classes_arguments = single_partition.flat_map do |test_target, classes|
        all_classes = test_time_for_partitions[test_target].keys.to_set
        (all_classes - classes.to_set).sort.map { |test_class| "-skip-testing:#{test_target}/#{test_class}" }
      end

      skipped_target_arguments + skipped_classes_arguments
    end

    def xcodebuild_only_arguments_for_a_partition_set(partition_set)
      partition_set.map { |partition| xctool_only_arguments(partition) }
    end
  end
end
