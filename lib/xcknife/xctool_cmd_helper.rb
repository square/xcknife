require 'pp'
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
    def xcodebuild_only_arguments(single_partition)
      single_partition.flat_map do |test_target, classes|
        classes.sort.map do |clazz|
          "-only-testing:#{test_target}/#{clazz}"
        end

      end
    end

    def xcodebuild_only_arguments_for_a_partition_set(partition_set)
      partition_set.map { |partition| xctool_only_arguments(partition) }
    end
  end
end