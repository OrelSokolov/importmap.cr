# importmap.cr — порт importmap-rails 2.2.3 (pin / pin_all_from)

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Порт ядра гема `importmap-rails` (версия 2.2.3 — парная Rails 8.1):
DSL пиннинга JS-модулей + хелперы тегов. Неймспейс `Importmap` — 1:1.

## Статус (P0, 2026-10-05)

Оракул: `oracle/importmap_cases.rb` → `oracle/importmap_expected.yml`
(21 кейс, сняты с настоящего importmap-rails 2.2.3 + actionview 8.1.4;
резолвер — стаб `path_to_asset` → `/javascripts/<path>`, поведение Rails
без sprockets/propshaft), зеркало — `spec/importmap_spec.cr`.
Сюита — **17 examples, 0 failures**, байты вывода — байт-в-байт.

Состав:
- `Importmap::Map` (`src/map.cr`): `pin` (`to:`, `preload:` — Bool|String
  entrypoint), `pin_all_from` (`under:`, `to:`), block-DSL `draw`,
  `to_json` (pretty-JSON как Ruby `JSON.pretty_generate`), 
  `preloaded_module_paths` (+ entry_point-фильтрация), `digest` (SHA1),
  кэш `cache_as`/`clear_cache`
- `Importmap::ImportmapTagsHelper` (`src/tags_helper.cr`):
  `javascript_importmap_tags` (inline importmap + modulepreload + import),
  `javascript_inline_importmap_tag`, `javascript_import_module_tag`,
  `javascript_importmap_module_preload_tags`,
  `javascript_module_preload_tag`; резолвер `path_to_asset` →
  `compute_asset_path` (`/javascripts/x.js`, URL насквозь)
- глобальная `Importmap.map` — аналог `Rails.application.importmap`;
  относительные `dir` в `pin_all_from` резолвятся от `Importmap::Map.root`
  (railties ставит её в `CRails.root`)

Интеграция (railties):
- хелперы включены в `ActionController::Base` (контроллер — view-контекст)
- `CRails::Middleware::Static` отдаёт `/javascripts/*` из `app/javascript`
- `crails new`: layout с `<%= javascript_importmap_tags %>`,
  `config/importmap.cr` (`map.pin "application"`),
  `app/javascript/application.js`

## Отклонения (задокументированы)

- `draw(path)` с рубишным конфигом (instance_eval) невозможен — только
  block-DSL: `Importmap.map.draw do |map| map.pin "application" end`
- SRI-интежрити (`enable_integrity!`, `integrity:`) — P2 (нет asset
  pipeline с поддержкой integrity; поле опущено)
- packager (`bin/importmap pin/unpin/update`, jsDelivr/npm) — P2 (нужен
  HTTP-клиент)
- reloader (`EventedFileUpdateChecker`) — не нужен (compile-time)
- CSP-nonce опущен (нет CSP-слоя; nonce всегда nil — как в оракуле
  с nil-request)
- `preloaded_module_packages` (hash путей в MappedFile) опущен — без
  integrity достаточно `preloaded_module_paths` (ключи того же hash)
- резолвер не падает на отсутствующих файлах (нет манифеста) — ветка
  `rescuable_asset_errors` всегда пропускается

## Quirk'и гема, сохранённые 1:1 (подтверждены оракулом)

- glob `**/*.js{,m}` пиннит `.js`/`.jsm`, но НЕ `.mjs`
- кэш `preloaded_module_*` с дефолтным `cache_key` игнорирует смену
  `entry_point` (кейс `preload_paths_admin`); хелперы передают
  `cache_key: entry_point`, как гем

## Зависимости

action_view.cr (TagHelper/`compute_asset_path`, SafeString).

Бенч: `bench/importmap_bench.{cr,rb}` (пара с настоящим гемом) →
`../bench/results/204-importmap.md` (~11.6× на рендере тегов).
