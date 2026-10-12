# Mirror of oracle/importmap_expected.yml (captured from importmap-rails
# 2.2.3 + actionview 8.1.4 via oracle/importmap_cases.rb). Same case IDs,
# same expectations. The fixture mirrors the oracle's app/javascript tree.

require "spec"
require "../src/importmap_cr"
require "file_utils"

IMPORTMAP_EXPECTED = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/importmap_expected.yml").each_line do |line|
    next unless line.includes?('\t')
    id, value = line.split('\t', 2)
    hash[id] = value.chomp.gsub("\\n", "\n")
  end
  hash
end

FIXTURE = File.join(Dir.tempdir, "crails_importmap_spec_#{Random::Secure.hex(4)}")
%w[
  app/javascript
  app/javascript/controllers
  app/javascript/lib/util
  app/javascript/lib/deep
].each { |d| FileUtils.mkdir_p(File.join(FIXTURE, d)) }

{
  "app/javascript/application.js"      => "",
  "app/javascript/controllers/index.js" => "",
  "app/javascript/controllers/greet.js" => "",
  "app/javascript/lib/util/index.mjs"   => "",
  "app/javascript/lib/deep/nested.js"  => "",
}.each { |f, c| File.write(File.join(FIXTURE, f), c) }

# Контекст рендера: хелперы ActionView + importmap (resolver = self).
class ImportmapSpecContext
  include ActionView::Helpers
  include Importmap::ImportmapTagsHelper
end

VIEW = ImportmapSpecContext.new

MAP = Importmap::Map.new.draw do |map|
  map.pin "application"
  map.pin "admin", to: "somewhere/admin.js"
  map.pin "chart", to: "https://cdn.skypack.dev/chart.js"
  map.pin "not_needed", to: "nn.js", preload: false
  map.pin "admin_only", to: "ao.js", preload: "admin"
  map.pin_all_from File.join(FIXTURE, "app/javascript/controllers"), under: "controllers"
  map.pin_all_from File.join(FIXTURE, "app/javascript/lib"), under: "lib", to: "vendor/lib"
end

CACHE_MAP = Importmap::Map.new.draw { |map| map.pin "one" }

# Спек-примеры выполняются в at_exit — после FileUtils.rm_rf внизу
# файла. Прогреваем все зависящие от фикстуры кэши eagerly, пока дерево
# существует (тот же приём, что и vite_spec.cr с манифестом).
MAP.to_json(VIEW)
MAP.preloaded_module_paths(VIEW)
MAP.preloaded_module_paths(VIEW, entry_point: "application", cache_key: "application")
MAP.preloaded_module_paths(VIEW, entry_point: "admin", cache_key: "admin")

def importmap_case(id)
  begin
    yield
  rescue ex : ArgumentError
    "raise:#{ex.class.name}"
  end.to_s
end

describe "importmap-rails 2.2.3 oracle" do
  it "json_empty" do
    importmap_case("x") { Importmap::Map.new.to_json(VIEW) }
      .should eq IMPORTMAP_EXPECTED["json_empty"]
  end

  it "json_map" do
    importmap_case("x") { MAP.to_json(VIEW) }
      .should eq IMPORTMAP_EXPECTED["json_map"]
  end

  it "pin_redefinition" do
    Importmap::Map.new.draw { |map|
      map.pin "x"
      map.pin "x", to: "y.js"
    }.to_json(VIEW).should eq IMPORTMAP_EXPECTED["pin_redefinition"]
  end

  # Quirk гема: дефолтный cache_key одинаков — второй вызов с другим
  # entry_point отдаёт закэшированный результат (без admin_only).
  it "preload_paths_application" do
    MAP.preloaded_module_paths(VIEW).inspect
      .should eq IMPORTMAP_EXPECTED["preload_paths_application"]
  end

  it "preload_paths_admin" do
    MAP.preloaded_module_paths(VIEW, entry_point: "admin").inspect
      .should eq IMPORTMAP_EXPECTED["preload_paths_admin"]
  end

  it "digest_map" do
    MAP.digest(VIEW).should eq IMPORTMAP_EXPECTED["digest_map"]
  end

  it "cache_before" do
    CACHE_MAP.to_json(VIEW).should eq IMPORTMAP_EXPECTED["cache_before"]
  end

  it "cache_after_repin" do
    CACHE_MAP.pin "two"
    CACHE_MAP.to_json(VIEW).should eq IMPORTMAP_EXPECTED["cache_after_repin"]
  end

  it "tags_full" do
    VIEW.javascript_importmap_tags("application", MAP).to_s
      .should eq IMPORTMAP_EXPECTED["tags_full"]
  end

  it "tags_full_entry_admin" do
    VIEW.javascript_importmap_tags("admin", MAP).to_s
      .should eq IMPORTMAP_EXPECTED["tags_full_entry_admin"]
  end

  it "tags_inline" do
    VIEW.javascript_inline_importmap_tag(MAP.to_json(VIEW)).to_s
      .should eq IMPORTMAP_EXPECTED["tags_inline"]
  end

  it "tags_inline_custom_json" do
    VIEW.javascript_inline_importmap_tag(%({"imports":{"x":"/x.js"}})).to_s
      .should eq IMPORTMAP_EXPECTED["tags_inline_custom_json"]
  end

  it "tags_import_single" do
    VIEW.javascript_import_module_tag("application").to_s
      .should eq IMPORTMAP_EXPECTED["tags_import_single"]
  end

  it "tags_import_multi" do
    VIEW.javascript_import_module_tag("a", "b").to_s
      .should eq IMPORTMAP_EXPECTED["tags_import_multi"]
  end

  it "tags_preload" do
    VIEW.javascript_importmap_module_preload_tags(MAP, entry_point: "application").to_s
      .should eq IMPORTMAP_EXPECTED["tags_preload"]
  end

  it "tags_preload_admin" do
    VIEW.javascript_importmap_module_preload_tags(MAP, entry_point: "admin").to_s
      .should eq IMPORTMAP_EXPECTED["tags_preload_admin"]
  end

  it "tags_module_preload_tag" do
    VIEW.javascript_module_preload_tag("/javascripts/a.js", "/javascripts/b.js").to_s
      .should eq IMPORTMAP_EXPECTED["tags_module_preload_tag"]
  end
end

FileUtils.rm_rf(FIXTURE)

# Documented deviations (also in src/map.cr / PLAN.md):
# - draw(path) file-form is impossible in Crystal: block-DSL only.
# - SRI integrity (enable_integrity!) — P2 (no asset pipeline).
# - The resolver never raises for missing files (no manifest).
# - preloaded_module_packages omitted (only paths, integrity-less).
