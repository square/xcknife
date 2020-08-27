# frozen_string_literal: true

require 'fileutils'

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'
RuboCop::RakeTask.new

task default: %w[spec rubocop]

desc 'Builds TestDumper.dylib'
task :build_test_dumper do
  target_dir = File.join(File.dirname(__FILE__), 'TestDumper')
  Dir.chdir(target_dir) do
    system './build.sh'
    FileUtils.copy_file('./testdumperbuild/Build/Products/Debug-iphonesimulator/TestDumper.framework/TestDumper', './TestDumper.dylib')
    puts 'TestDumper.dylib was created successfully'
  end
end

desc 'Release wih test_dumper'
task gem_release: %i[build_test_dumper build] do
  system 'gem push pkg/xcknife-*.gem'
end
