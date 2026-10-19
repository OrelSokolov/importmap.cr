# importmap.cr — порт importmap-rails 2.2.3 (pin / pin_all_from,
# inline importmap + modulepreload теги).
#
# Оракул: oracle/importmap_cases.rb → oracle/importmap_expected.yml
# (сняты с настоящего гема importmap-rails 2.2.3 + actionview 8.1.4),
# зеркало — spec/importmap_spec.cr. Подробности — PLAN.md.

require "action_view_cr"
require "./map"
require "./tags_helper"
require "attr_reader_cr"

module Importmap
    @@map : Map?

    # Глобальная карта приложения — аналог Rails.application.importmap.
    # Приложение наполняет её в config/importmap.cr:
    #   Importmap.map.draw do |map|
    #     map.pin "application"
    #   end
    def self.map : Map
      @@map ||= Map.new
    end

    def self.map=(map : Map) : Map
      @@map = map
    end
end
