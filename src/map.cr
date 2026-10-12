# Importmap::Map — порт importmap-rails 2.2.3 lib/importmap/map.rb.
#
# Оракул: oracle/importmap_cases.rb → oracle/importmap_expected.yml
# (сняты с настоящего importmap-rails 2.2.3 + actionview 8.1.4), зеркало —
# spec/importmap_spec.cr.
#
# Wire-формат 1:1 (байты из оракула):
# - to_json: pretty-JSON как Ruby JSON.pretty_generate (2 пробела,
#   ": " после ключа, пустой "imports": {} в одну строку);
# - порядок модулей: insertion-порядок pin'ов, затем раскрытые
#   директории (glob sort);
# - кэш cache_as: повторный вызов с тем же cache_key (включая дефолтный)
#   игнорирует смену entry_point — quirk гема, подтверждён оракулом
#   (кейс preload_paths_admin);
# - glob "*.js{,m}" как в геме: .mjs НЕ пиннится (только .js/.jsm) —
#   сохранено 1:1 (кейс с lib/util/index.mjs).
#
# Задокументированные отклонения от гема (P2):
# - draw(path) с рубишным конфигом (instance_eval) невозможен — только
#   block-DSL: Importmap.map.draw { |map| map.pin "application" };
# - SRI-интежнити (enable_integrity!, integrity:) — нет asset pipeline
#   с поддержкой integrity, поле опущено;
# - резолвер не падает на отсутствующих файлах (нет манифеста) —
#   ветка rescuable_asset_errors всегда пропускается;
# - preloaded_module_packages (hash путей в MappedFile) опущен —
#   без integrity достаточно preloaded_module_paths (ключи того же hash).

require "json"
require "digest/sha1"

module Importmap
  # Объект, умеющий резолвить пути ассетов (контекст вьюхи с
  # path_to_asset, как в Rails: resolver = self).
  module AssetResolver
    abstract def path_to_asset(path : String) : String
  end

  class Map
    # Корень для относительных dir в pin_all_from (аналог Rails.root).
    class_property root : String = Dir.current

    # preload: true | false | "entry_point" — как в геме.
    alias Preload = Bool | String | Array(String)
    alias EntryPoint = String | Array(String)

    struct MappedFile
      getter name : String
      getter path : String
      getter preload : Preload

      def initialize(@name, @path, @preload)
      end
    end

    struct MappedDir
      getter dir : String
      getter under : String?
      getter path : String?
      getter preload : Preload

      def initialize(@dir, @under, @path, @preload)
      end
    end

    @integrity = false # не поддержан (P2), поле сохранено для паритета веток
    @packages = {} of String => MappedFile
    @directories = {} of String => MappedDir
    @cache = {} of String => (String | Array(String))

    getter packages : Hash(String, MappedFile)
    getter directories : Hash(String, MappedDir)

    # Block-DSL вместо instance_eval-конфига (см. отклонения):
    #
    #   Importmap.map.draw do |map|
    #     map.pin "application"
    #     map.pin_all_from "app/javascript/controllers", under: "controllers"
    #   end
    def draw(&) : self
      yield self
      self
    end

    def pin(name : String, to : String? = nil, preload : Preload = true) : Nil
      clear_cache
      @packages[name] = MappedFile.new(name: name, path: to || "#{name}.js", preload: preload)
    end

    def pin_all_from(dir : String, under : String? = nil, to : String? = nil,
                     preload : Preload = true) : Nil
      clear_cache
      @directories[dir] = MappedDir.new(dir: dir, under: under, path: to, preload: preload)
    end

    # Pretty-JSON import map: {"imports": {name → resolved path}}.
    def to_json(resolver : AssetResolver, cache_key : String = "json") : String
      cache_as(cache_key) do
        pretty_imports(resolve_asset_paths(expanded_packages_and_directories, resolver))
      end.as(String)
    end

    # Пути модулей с preload: true (или совпадающим entry_point), в
    # порядке определения.
    def preloaded_module_paths(resolver : AssetResolver, entry_point : EntryPoint = "application",
                               cache_key : String = "preloaded_module_paths") : Array(String)
      cache_as(cache_key) do
        expanded_preloading_packages_and_directories(entry_point)
          .map { |_, package| resolver.path_to_asset(package.path) }
      end.as(Array(String))
    end

    # SHA1 от to_json — для etag (как в геме).
    def digest(resolver : AssetResolver) : String
      Digest::SHA1.hexdigest(to_json(resolver))
    end

    def clear_cache : Nil
      @cache.clear
    end

    private def cache_as(name : String, &)
      if result = @cache[name]?
        result
      else
        @cache[name] = yield
      end
    end

    private def expanded_packages_and_directories : Hash(String, MappedFile)
      expanded = @packages.dup
      expand_directories_into(expanded)
      expanded
    end

    private def expanded_preloading_packages_and_directories(entry_point : EntryPoint) : Hash(String, MappedFile)
      expanded_packages_and_directories.select do |_, mapping|
        preload?(mapping.preload, entry_point)
      end
    end

    private def preload?(preload : Preload, entry_point : EntryPoint) : Bool
      entry_points = entry_point.is_a?(Array) ? entry_point : [entry_point]
      case preload
      when Bool
        preload
      else
        preloads = preload.is_a?(Array) ? preload : [preload.as(String)]
        !(preloads & entry_points).empty?
      end
    end

    private def expand_directories_into(paths : Hash(String, MappedFile)) : Nil
      @directories.each_value do |mapping|
        absolute_path = absolute_root_of(mapping.dir)
        next unless Dir.exists?(absolute_path)
        find_javascript_files_in_tree(absolute_path).each do |filename|
          module_filename = filename[(absolute_path.size + 1)..]
          module_name = module_name_from(module_filename, mapping)
          module_path = module_path_from(module_filename, mapping)
          paths[module_name] = MappedFile.new(
            name: module_name,
            path: module_path,
            preload: mapping.preload
          )
        end
      end
    end

    # "controllers/index" → "controllers", "util/index" → "util",
    # "index" → "" → отбрасывается (join без пустых).
    private def module_name_from(filename : String, mapping : MappedDir) : String
      base = filename.sub(/\.[^\/]+$/, "").gsub(/(?:\/|^)index$/, "")
      parts = [mapping.under, base.empty? ? nil : base].compact
      parts.reject(&.empty?).join("/")
    end

    private def module_path_from(filename : String, mapping : MappedDir) : String
      prefix = mapping.path || mapping.under
      [prefix, filename].compact.reject(&.empty?).join("/")
    end

    # Glob гема "**/*.js{,m}": .js и .jsm (НЕ .mjs), сортировка как Dir[].
    private def find_javascript_files_in_tree(path : String) : Array(String)
      files = Dir.glob(File.join(path, "**/*.js")) + Dir.glob(File.join(path, "**/*.jsm"))
      files.sort.select { |f| File.file?(f) }
    end

    private def absolute_root_of(path : String) : String
      path.starts_with?('/') ? path : File.join(Map.root, path)
    end

    private def resolve_asset_paths(paths : Hash(String, MappedFile),
                                    resolver : AssetResolver) : Hash(String, String)
      resolved = {} of String => String
      paths.each { |name, mapping| resolved[name] = resolver.path_to_asset(mapping.path) }
      resolved
    end

    # Байт-в-байт с Ruby JSON.pretty_generate для хеша с одним ключом
    # "imports" (вставка insertion-порядка).
    private def pretty_imports(map : Hash(String, String)) : String
      String.build do |io|
        io << "{\n  \"imports\": "
        if map.empty?
          io << "{}"
        else
          io << "{\n"
          map.each_with_index do |(key, value), index|
            io << "    " << key.to_json << ": " << value.to_json
            io << ",\n" if index < map.size - 1
          end
          io << "\n  }"
        end
        io << "\n}"
      end
    end
  end
end
