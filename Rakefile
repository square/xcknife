require 'rspec/core/rake_task'
require "bundler/gem_tasks"
require 'fileutils'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Builds TestDumper.dylib"
task :build_test_dumper do
  target_dir = File.join(File.dirname(__FILE__), "TestDumper")
  Dir.chdir(target_dir) do
    system "./build.sh"
    FileUtils.copy_file("./testdumperbuild/Build/Products/Release-iphonesimulator/TestDumper.framework/TestDumper", "./TestDumper.dylib")
    puts "TestDumper.dylib was created successfully"
  end
end

desc "Release wih test_dumper"
task :gem_release => [:build_test_dumper, :build] do
  system 'gem push pkg/xcknife-*.gem'
end