; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/base.x -- what the entry and the specs reach
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module roguelike/base)

(import roguelike/data data-load data-all data-one data-get data-prop data-prop1 data-trait? data-glyph)
(import roguelike/map
  map-rows map-cols map-rooms map-down map-up map-tile map-seen? map-visible? map-walkable? room-lit?
  map-room-at tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up)
(import roguelike/dungeon dungeon-generate)
(import roguelike/state
  game-depth game-map game-player game-creatures game-creatures! game-floor game-floor! game-pack game-pack!
  game-messages game-turn game-ask game-over game-epitaph game-known game-deepest game-log
  player-r player-c player-at! player-hp player-hp! player-hpmax player-str player-level player-exp player-gold
  player-food player-food! player-condition player-weapon player-armour player-rings
  creature-make creature-r creature-c creature-at! creature-hp creature-hp! creature-state creature-state!
  creature-name item-make item-name item-count item-charges item-enchant item-letter item-r item-c item-at!
  item-class state-say!)
(import roguelike/creatures creatures-kinds)
(import roguelike/items items-name items-new items-known?)
(import roguelike/game game-make game-key! game-more! game-score game-help)
(import roguelike/draw game-draw!)
(import roguelike/save save-write! save-read save-score! save-scores)
(import roguelike/cli roguelike-main roguelike-version)

(provide roguelike/base roguelike-version roguelike-main
  data-load data-all data-one data-get data-prop data-prop1 data-trait? data-glyph
  map-rows map-cols map-rooms map-down map-up map-tile map-seen? map-visible? map-walkable? room-lit?
  map-room-at tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up
  dungeon-generate
  game-make game-key! game-more! game-score game-help game-draw!
  game-depth game-map game-player game-creatures game-creatures! game-floor game-floor! game-pack game-pack!
  game-messages game-turn game-ask game-over game-epitaph game-known game-deepest game-log
  player-r player-c player-at! player-hp player-hp! player-hpmax player-str player-level player-exp player-gold
  player-food player-food! player-condition player-weapon player-armour player-rings
  creature-make creature-r creature-c creature-at! creature-hp creature-hp! creature-state creature-state!
  creature-name item-make item-name item-count item-charges item-enchant item-letter item-r item-c item-at!
  item-class state-say!
  items-name items-new items-known? creatures-kinds
  save-write! save-read save-score! save-scores)
