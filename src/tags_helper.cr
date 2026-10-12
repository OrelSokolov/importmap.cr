# Importmap::ImportmapTagsHelper — порт importmap-rails 2.2.3
# app/helpers/importmap/importmap_tags_helper.rb.
#
# Wire-формат 1:1 (байты из оракула):
# - <script type="importmap" data-turbo-track="reload">JSON</script>
#   (JSON не экранируется — аналог .html_safe в геме);
# - <script type="module">import "x"</script>, модули через "\n";
# - <link rel="modulepreload" href="..."> (без закрывающего слэша,
#   dot-форма tag.link гема), линки через "\n";
# - группы javascript_importmap_tags склеиваются "\n".
#
# Отклонения (P2): CSP-nonce опущен (нет CSP-слоя, nonce всегда nil,
# как в оракуле с nil-request).

module Importmap
  module ImportmapTagsHelper
    include AssetResolver

    # Полный стек для entrypoint: inline importmap + modulepreload
    # пиннутых модулей + import-строка entrypoint.
    def javascript_importmap_tags(entry_point : String = "application",
                                  importmap : Map = Importmap.map) : ActionView::SafeString
      parts = [
        javascript_inline_importmap_tag(importmap.to_json(resolver: self)),
        javascript_importmap_module_preload_tags(importmap, entry_point: entry_point),
        javascript_import_module_tag(entry_point),
      ]
      ActionView::SafeString.new(parts.map(&.to_s).join("\n"))
    end

    # Inline importmap из готовой JSON-строки (или из дефолтной карты).
    def javascript_inline_importmap_tag(importmap_json : String? = nil) : ActionView::SafeString
      json = importmap_json || Importmap.map.to_json(resolver: self)
      attrs = tag_options({"type" => "importmap", "data-turbo-track" => "reload"})
      ActionView::SafeString.new("<script#{attrs}>#{json}</script>")
    end

    # import "x" внутри <script type="module">.
    def javascript_import_module_tag(*module_names : String) : ActionView::SafeString
      imports = module_names.map { |m| %(import "#{m}") }.join("\n")
      attrs = tag_options({"type" => "module"})
      ActionView::SafeString.new("<script#{attrs}>#{imports}</script>")
    end

    # Modulepreload-линки для пиннутых модулей с preload: true (или
    # совпадающим entry_point). cache_key = entry_point — как в геме.
    def javascript_importmap_module_preload_tags(importmap : Map = Importmap.map,
                                                 entry_point : String = "application") : ActionView::SafeString
      paths = importmap.preloaded_module_paths(
        resolver: self, entry_point: entry_point, cache_key: entry_point)
      module_preload_links(paths)
    end

    # Modulepreload-линки для явных путей.
    def javascript_module_preload_tag(*paths : String) : ActionView::SafeString
      module_preload_links(paths.to_a)
    end

    # Резолвер путей для Importmap::Map (resolver: self, как в Rails):
    # поведение Rails без sprockets/propshaft — абсолютные пути и URL
    # проходят насквозь, остальное → /javascripts/<path>.
    def path_to_asset(path : String) : String
      compute_asset_path(path) { |s| "javascripts/#{s}" }
    end

    private def module_preload_links(paths : Array(String)) : ActionView::SafeString
      ActionView::SafeString.new(paths.map { |path|
        attrs = tag_options({"rel" => "modulepreload", "href" => path})
        "<link#{attrs}>"
      }.join("\n"))
    end
  end
end
