# importmap.cr

A Crystal port of the core of **importmap-rails 2.2.3** (the Rails 8.1
companion gem) — the JS module pinning DSL plus importmap tag helpers.
Namespace `Importmap` mirrors the original 1:1. Output is byte-identical
to the gem (oracle recorded with real importmap-rails 2.2.3 +
actionview 8.1.4; the `path_to_asset` resolver stubbed to
`/javascripts/<path>`, i.e. Rails behavior without sprockets/propshaft).

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

## Installation

```yaml
dependencies:
  importmap_cr:
    github: OrelSokolov/importmap.cr
```

```sh
shards install
```

Depends on `action_view.cr` (TagHelper / `compute_asset_path`,
SafeString).

## Usage

```crystal
Importmap.map.draw do |map|
  map.pin "application", preload: true
  map.pin "chart", to: "chart.js"
  map.pin_all_from "app/javascript/controllers", under: "controllers"
end
```

```erb
<%= javascript_importmap_tags %>   <!-- inline importmap + modulepreload + import -->
```

Integration with railties: helpers are included into
`ActionController::Base`, `CRails::Middleware::Static` serves
`/javascripts/*` from `app/javascript`, and `crails new` generates a
layout with `javascript_importmap_tags`, a `config/importmap.cr` and
`app/javascript/application.js`.

## Feature comparison vs importmap-rails 2.2.3

| Feature | Original (importmap-rails) | Port (importmap.cr) | Status |
|---|---|---|---|
| `pin` (`to:`, `preload:` Bool\|String entrypoint) | ✅ | Same | ✅ |
| `pin_all_from` (`under:`, `to:`) | ✅ | Same; relative `dir` resolved from `Importmap::Map.root` (railties sets it to `CRails.root`) | ✅ |
| `draw` DSL | `draw(path)` reads a Ruby config via instance_eval | Block DSL only: `Importmap.map.draw do \|map\| ... end` | 🔶 |
| `to_json` (pretty, like Ruby `JSON.pretty_generate`) | ✅ | Same | ✅ |
| `preloaded_module_paths` (+ entry-point filter) | ✅ | Same, incl. the gem quirk: default `cache_key` ignores `entry_point` changes (helpers pass `cache_key: entry_point`, as the gem does) | ✅ |
| `digest` (SHA1), `cache_as` / `clear_cache` | ✅ | Same | ✅ |
| `javascript_importmap_tags`, `javascript_inline_importmap_tag`, `javascript_import_module_tag`, `javascript_importmap_module_preload_tags`, `javascript_module_preload_tag` | ✅ | Same, byte-identical output | ✅ |
| Asset resolution (`path_to_asset` → `compute_asset_path`) | ✅ (sprockets/propshaft) | `/javascripts/x.js`, URLs pass through; does not fail on missing files (no manifest) | 🔶 |
| SRI integrity (`enable_integrity!`, `integrity:`) | ✅ | P2 — omitted (no asset pipeline with integrity support) | ⬜ |
| Packager (`bin/importmap pin/unpin/update`, jsDelivr/npm) | ✅ | P2 (needs an HTTP client) | ⬜ |
| Reloader (`EventedFileUpdateChecker`) | ✅ | Not needed (compile-time) | — |
| CSP nonce in tags | ✅ | Omitted (no CSP layer; nonce always nil — matches the nil-request oracle) | ❌ (equivalent: none, until a CSP layer exists) |
| `preloaded_module_packages` | ✅ | Omitted — `preloaded_module_paths` suffices without integrity | ❌ |
| Glob quirk: `**/*.js{,m}` pins `.js`/`.jsm` but not `.mjs` | ✅ (quirk) | Preserved 1:1 (oracle-confirmed) | ✅ |

## Testing

```sh
crystal spec   # 17 examples, 0 failures; output byte-for-byte
```

Oracle: `oracle/importmap_cases.rb` → `oracle/importmap_expected.yml`
(21 cases). Benchmarks: `bench/importmap_bench.{cr,rb}` against the real
gem — ~11.6× faster on tag rendering (`bench/results/204-importmap.md`).
