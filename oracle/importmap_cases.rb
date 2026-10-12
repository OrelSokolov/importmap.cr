# Oracle cases for the importmap port (pin / pin_all_from, importmap-rails).
#
# Run against the ORIGINAL gem (importmap-rails 2.2.3 + actionview 8.1.4):
#   ruby oracle/importmap_cases.rb > oracle/importmap_expected.yml
#
# Each line: "<case_id>\t<value>". Mirrored 1:1 in
# importmap.cr/spec/importmap_spec.cr. The fixture tree mirrors a real
# app/javascript layout (nested dirs, index files, .mjs).
#
# Resolver stub mirrors crails' compute_asset_path (Rails without
# sprockets/propshaft): absolute paths and full URLs pass through,
# everything else maps to /javascripts/<path>.

gem "importmap-rails", "= 2.2.3"
gem "actionview", "= 8.1.4"
gem "actionpack", "= 8.1.4"
require "action_view"
require "json"
require "digest"
gem_dir = Gem::Specification.find_by_name("importmap-rails", "= 2.2.3").gem_dir
module Importmap; end
require File.join(gem_dir, "lib/importmap/map")
require File.join(gem_dir, "app/helpers/importmap/importmap_tags_helper")

def render(v)
  case v
  when String then v.gsub("\n", "\\n")
  else v.inspect
  end
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

require "fileutils"
ROOT = File.expand_path("importmap_fixture", __dir__)
FileUtils.rm_rf(ROOT)
%w[
  app/javascript
  app/javascript/controllers
  app/javascript/lib/util
  app/javascript/lib/deep
].each { |d| FileUtils.mkdir_p(File.join(ROOT, d)) }

{
  "app/javascript/application.js"            => "",
  "app/javascript/controllers/index.js"       => "",
  "app/javascript/controllers/greet.js"       => "",
  "app/javascript/lib/util/index.mjs"        => "",
  "app/javascript/lib/deep/nested.js"        => "",
}.each { |f, c| File.write(File.join(ROOT, f), c) }

# Rails without an asset pipeline: plain paths, URLs untouched.
RESOLVER = Object.new
def RESOLVER.path_to_asset(path)
  path.start_with?("/") || path.include?("://") ? path : "/javascripts/#{path}"
end

class ImportmapOracleView < ActionView::Base
  include Importmap::ImportmapTagsHelper
  def path_to_asset(path)
    path.start_with?("/") || path.include?("://") ? path : "/javascripts/#{path}"
  end
end

VIEW = ImportmapOracleView.new(nil, [], nil)

MAP = Importmap::Map.new.draw do
  pin "application"
  pin "admin", to: "somewhere/admin.js"
  pin "chart", to: "https://cdn.skypack.dev/chart.js"
  pin "not_needed", to: "nn.js", preload: false
  pin "admin_only", to: "ao.js", preload: "admin"
  pin_all_from File.join(ROOT, "app/javascript/controllers"), under: "controllers"
  pin_all_from File.join(ROOT, "app/javascript/lib"), under: "lib", to: "vendor/lib"
end

# --- map: json ------------------------------------------------------------

case_run("json_empty") { Importmap::Map.new.to_json(resolver: RESOLVER) }
case_run("json_map") { MAP.to_json(resolver: RESOLVER) }

case_run("pin_redefinition") do
  Importmap::Map.new.draw do
    pin "x"
    pin "x", to: "y.js"
  end.to_json(resolver: RESOLVER)
end

# --- map: preloading ------------------------------------------------------

case_run("preload_paths_application") { MAP.preloaded_module_paths(resolver: RESOLVER) }
case_run("preload_paths_admin") do
  MAP.preloaded_module_paths(resolver: RESOLVER, entry_point: "admin")
end

case_run("digest_map") { MAP.digest(resolver: RESOLVER) }

# --- map: cache -----------------------------------------------------------

CACHE = Importmap::Map.new.draw { pin "one" }
case_run("cache_before") { CACHE.to_json(resolver: RESOLVER) }
case_run("cache_after_repin") do
  CACHE.pin "two"
  CACHE.to_json(resolver: RESOLVER)
end

# --- helper tags ----------------------------------------------------------

case_run("tags_full") { VIEW.javascript_importmap_tags("application", importmap: MAP) }
case_run("tags_full_entry_admin") do
  VIEW.javascript_importmap_tags("admin", importmap: MAP)
end
case_run("tags_inline") do
  VIEW.javascript_inline_importmap_tag(MAP.to_json(resolver: VIEW))
end
case_run("tags_inline_custom_json") do
  VIEW.javascript_inline_importmap_tag('{"imports":{"x":"/x.js"}}')
end
case_run("tags_import_single") { VIEW.javascript_import_module_tag("application") }
case_run("tags_import_multi") { VIEW.javascript_import_module_tag("a", "b") }
case_run("tags_preload") do
  VIEW.javascript_importmap_module_preload_tags(MAP, entry_point: "application")
end
case_run("tags_preload_admin") do
  VIEW.javascript_importmap_module_preload_tags(MAP, entry_point: "admin")
end
case_run("tags_module_preload_tag") do
  VIEW.javascript_module_preload_tag("/javascripts/a.js", "/javascripts/b.js")
end
