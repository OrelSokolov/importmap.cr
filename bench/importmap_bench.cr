# Micro-bench: render javascript_importmap_tags for a 20-pin map,
# against importmap_cr (pair of bench/importmap_bench.rb).

require "../src/importmap_cr"

class BenchView
  include ActionView::Helpers
  include Importmap::ImportmapTagsHelper
end

MAP = Importmap::Map.new.draw do |map|
  20.times { |i| map.pin "module#{i}", to: "dir#{i}/module#{i}.js" }
end
VIEW = BenchView.new

raise "bad render" unless VIEW.javascript_importmap_tags("application", MAP).to_s.includes?(%(<script type="importmap"))

n = 0
t0 = Time.instant
while Time.instant - t0 < 2.seconds
  VIEW.javascript_importmap_tags("application", MAP)
  n += 1
end
printf "crystal renders/sec: %.0f\n", n / 2.0
