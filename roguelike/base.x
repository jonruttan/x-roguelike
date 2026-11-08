; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/base.x -- what the entry and the specs reach
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module roguelike/base)

(import roguelike/data data-load data-region data-all data-one data-get data-prop data-prop1 data-trait? data-glyph
  data-choices data-chosen data-choice-text data-choose)
(import roguelike/map
  map-rows map-cols map-rooms map-places map-place-at map-down map-up map-tile map-seen? map-visible? map-walkable? room-lit?
  room-r0 room-c0 room-r1 room-c1 room-centre
  map-room-at map-light-radius! tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up
  tile-water tile-pillar tile-fall tile-dressed tile-hedge tile-gate tile-thicket tile-edge tile-bog tile-scar map-passable?)
(import roguelike/dungeon dungeon-generate)
(import roguelike/scale scale-rung scale-across scale-down scale-area scale-seconds scale-check!)
(import roguelike/state
  game-set game-depth game-map game-player game-creatures game-creatures! game-floor game-floor! game-pack game-pack!
  game-messages game-turn game-ask game-over game-epitaph game-known game-deepest game-log game-pages-placed
  game-quest-state game-placed game-sure game-traps game-traps! game-exploring?
  game-screen game-screens? game-kept game-kept-level game-hub game-screen-key game-screen-distance game-chain
  game-band band-name game-forms
  game-door game-inside game-level-key game-turn! game-clock game-clock! game-over! game-deepest! game-quest-state!
  game-below? game-region game-regions game-top-set game-screen-name
  player-r player-c player-at! player-hp player-hp! player-hpmax player-str player-level player-exp player-gold player-gold!
  player-food player-food! player-condition player-weapon player-armour player-rings
  creature-make creature-r creature-c creature-at! creature-hp creature-hp! creature-state creature-state!
  creature-name creature-glyph creature-trait? creature-carried state-a-kind item-make item-name item-count item-charges
  item-enchant item-letter item-letter! item-r item-c item-at!
  item-class state-say! state-dist state-adjacent?)
(import roguelike/creatures creatures-kinds creatures-place!)
(import roguelike/items items-name items-new items-known? items-spawn!)
(import roguelike/traps trap-make trap-found?)
(import roguelike/chain chain-where)
(import roguelike/game game-make game-key! game-explore! game-more! game-score game-score-lines game-score-text game-help)
(import roguelike/draw game-draw!)
(import roguelike/save save-write! save-read save-score! save-scores)
(import roguelike/cli roguelike-main roguelike-options roguelike-version)

(provide roguelike/base roguelike-version roguelike-main roguelike-options
  data-load data-region data-all data-one data-get data-prop data-prop1 data-trait? data-glyph
  data-choices data-chosen data-choice-text data-choose
  map-rows map-cols map-rooms map-places map-place-at map-down map-up map-tile map-seen? map-visible? map-walkable? room-lit?
  room-r0 room-c0 room-r1 room-c1 room-centre
  map-room-at map-light-radius! tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up
  tile-water tile-pillar tile-fall tile-dressed tile-hedge tile-gate tile-thicket tile-edge tile-bog tile-scar map-passable?
  dungeon-generate scale-rung scale-across scale-down scale-area scale-seconds scale-check!
  game-make game-key! game-explore! game-more! game-score game-score-lines game-score-text game-help game-draw!
  game-set game-depth game-map game-player game-creatures game-creatures! game-floor game-floor! game-pack game-pack!
  game-messages game-turn game-ask game-over game-epitaph game-known game-deepest game-log game-pages-placed
  game-quest-state game-placed game-sure game-traps game-traps! game-exploring?
  game-screen game-screens? game-kept game-kept-level game-hub game-screen-key game-screen-distance game-chain
  game-band band-name game-forms
  game-door game-inside game-level-key game-turn! game-clock game-clock! game-over! game-deepest! game-quest-state!
  game-below? game-region game-regions game-top-set game-screen-name
  player-r player-c player-at! player-hp player-hp! player-hpmax player-str player-level player-exp player-gold player-gold!
  player-food player-food! player-condition player-weapon player-armour player-rings
  creature-make creature-r creature-c creature-at! creature-hp creature-hp! creature-state creature-state!
  creature-name creature-glyph creature-trait? creature-carried state-a-kind item-make item-name item-count item-charges
  item-enchant item-letter item-letter! item-r item-c item-at!
  item-class state-say! state-dist state-adjacent?
  items-name items-new items-known? items-spawn! creatures-kinds creatures-place! trap-make trap-found? chain-where
  save-write! save-read save-score! save-scores)
