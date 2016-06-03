require_relative '../lib/xcknife'
require 'pp'

# Gem usage of xcknife. Functionaly equivalent to
# $ xcknife -p CommonTestTarget -p CommonTestTarget,iPadTestTarget 6 example/xcknife-exemplar-historical-data.json-stream example/xcknife-exemplar.json-stream
include XCKnife::XCToolCmdHelper
TARGET_PARTITIONS = {
  "AllTests" => ["CommonTestTarget", "iPadTestTarget"],
  "OnlyCommon" => ["CommonTestTarget"]
}

def run(historical_file, current_file)
  test_target_names = TARGET_PARTITIONS.keys
  knife = XCKnife::StreamParser.new(6, TARGET_PARTITIONS.values)
  result = knife.compute_shards_for_file(historical_file, current_file)
  partition_sets = result.test_maps
  puts "total = #{result.total_test_time}"
  puts "test times = #{result.test_times.inspect}"
  puts "stats = #{result.stats.to_h.pretty_inspect}"
  puts "imbalances = #{result.test_time_imbalances.to_h.inspect}"
  shard_number = 0
  puts "size = #{partition_sets.size}"
  puts "sizes = #{partition_sets.map(&:size).join(", ")}"
  partition_sets.each_with_index do |partition_set, i|
    target_name = test_target_names[i]
    partition_set.each do |partition|
      puts "target name for worker #{shard_number} = #{target_name}"
      puts "only is: #{xctool_only_arguments(partition).inspect}"
      shard_number += 1
    end
  end
end

run("xcknife-exemplar-historical-data.json-stream", "xcknife-exemplar.json-stream")
