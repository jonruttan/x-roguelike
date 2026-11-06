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
  room-r0 room-c0 room-r1 room-c1 room-centre
  map-room-at map-light-radius! tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up)
(import roguelike/dungeon dungeon-generate)
(import roguelike/state
  game-set game-depth game-map game-player game-creatures game-creatures! game-floor game-floor! game-pack game-pack!
  game-messages game-turn game-ask game-over game-epitaph game-known game-deepest game-log game-pages-placed
  game-quest-state game-placed game-traps game-traps! game-exploring?
  game-screen game-screens? game-kept game-kept-level game-hub game-screen-key game-screen-distance game-chain
  player-r player-c player-at! player-hp player-hp! player-hpmax player-str player-level player-exp player-gold
  player-food player-food! player-condition player-weapon player-armour player-rings
  creature-make creature-r creature-c creature-at! creature-hp creature-hp! creature-state creature-state!
  creature-name creature-glyph creature-trait? creature-carried item-make item-name item-count item-charges
  item-enchant item-letter item-letter! item-r item-c item-at!
  item-class state-say! state-dist state-adjacent?)
(import roguelike/creatures creatures-kinds creatures-place!)
(import roguelike/items items-name items-new items-known? items-spawn!)
(import roguelike/traps trap-make trap-found?)
(import roguelike/chain chain-where)
(import roguelike/game game-make game-key! game-explore! game-more! game-score game-help)
(import roguelike/draw game-draw!)
(import roguelike/save save-write! save-read save-score! save-scores)
(import roguelike/cli roguelike-main roguelike-options roguelike-version)

(provide roguelike/base roguelike-version roguelike-main roguelike-options
  data-load data-all data-one data-get data-prop data-prop1 data-trait? data-glyph
  map-rows map-cols map-rooms map-down map-up map-tile map-seen? map-visible? map-walkable? room-lit?
  room-r0 room-c0 room-r1 room-c1 room-centre
  map-room-at map-light-radius! tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up
  dungeon-generate
  game-make game-key! game-explore! game-more! game-score game-help game-draw!
  game-set game-depth game-map game-player game-creatures game-creatures! game-floor game-floor! game-pack game-pack!
  game-messages game-turn game-ask game-over game-epitaph game-known game-deepest game-log game-pages-placed
  game-quest-state game-placed game-traps game-traps! game-exploring?
  game-screen game-screens? game-kept game-kept-level game-hub game-screen-key game-screen-distance game-chain
  player-r player-c player-at! player-hp player-hp! player-hpmax player-str player-level player-exp player-gold
  player-food player-food! player-condition player-weapon player-armour player-rings
  creature-make creature-r creature-c creature-at! creature-hp creature-hp! creature-state creature-state!
  creature-name creature-glyph creature-trait? creature-carried item-make item-name item-count item-charges
  item-enchant item-letter item-letter! item-r item-c item-at!
  item-class state-say! state-dist state-adjacent?
  items-name items-new items-known? items-spawn! creatures-kinds creatures-place! trap-make trap-found? chain-where
  save-write! save-read save-score! save-scores)
