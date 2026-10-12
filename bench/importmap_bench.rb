#!/usr/bin/env ruby
# Micro-bench: render javascript_importmap_tags for a 20-pin map,
# against the real importmap-rails 2.2.3 (pair of bench/importmap_bench.cr).

gem "importmap-rails", "= 2.2.3"
gem "actionview", "= 8.1.4"
require "action_view"
require "json"
gem_dir = Gem::Specification.find_by_name("importmap-rails", "= 2.2.3").gem_dir
module Importmap; end
require File.join(gem_dir, "lib/importmap/map")
require File.join(gem_dir, "app/helpers/importmap/importmap_tags_helper")

class BenchView < ActionView::Base
  include Importmap::ImportmapTagsHelper
  def path_to_asset(path)
    path.start_with?("/") || path.include?("://") ? path : "/javascripts/#{path}"
  end
end

MAP = Importmap::Map.new.draw do
  20.times { |i| pin "module#{i}", to: "dir#{i}/module#{i}.js" }
end
VIEW = BenchView.new(nil, [], nil)

# warmup + correctness check
raise "bad render" unless VIEW.javascript_importmap_tags("application", importmap: MAP).include?("<script type=\"importmap\"")

n = 0
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
while Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 < 2.0
  VIEW.javascript_importmap_tags("application", importmap: MAP)
  n += 1
end
puts format("ruby renders/sec: %.0f", n / 2.0)
