require 'pp'
module XCKnife
  module XCToolCmdHelper
    def xctool_only_arguments(single_partition)
      single_partition.flat_map do |test_target, classes|
        ['-only', "#{test_target}:#{classes.sort.join(',')}"]
      end
    end

    def xctool_only_arguments_for_a_partition_set(partition_set)
      partition_set.map { |partition| xctool_only_arguments(partition) }
    end
  end
end