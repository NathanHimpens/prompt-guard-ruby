# frozen_string_literal: true

require "rake/testtask"

task default: :test

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
end

desc "Build the gem"
task :build do
  system "gem build prompt_guard.gemspec"
end

desc "Install the gem locally"
task install: :build do
  system "gem install ./prompt_guard-*.gem"
end
