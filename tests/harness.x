; # x-roguelike -- a roguelike on x-lang
;
; ## tests/harness.x -- what the spec harness adds to the dialect
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The lang kit's generator writes tests/lib/harness.gen.x: the dialect
; lang.xon declares, the bundle's root on the import path, then this file.
; Nothing is read at load: the harness is imaged, and the image is
; written from another directory.  x collects only when asked, so each
; level made or game started collects first.
(import roguelike/base roguelike-version roguelike-main
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
(import x/sys/gc)
(import x/sys/file)
(import x/type/vector)
(import x/num/random)
(import x/tui/screen)

; The classic set, read from the checkout once, at first use.
(def %spec-set-cell (Vector of ()))
(def spec-set
  (fn (_)
    (when (null? (Vector ref 0 %spec-set-cell)) (Vector set! 0 (data-load "data/classic") %spec-set-cell))
    (Vector ref 0 %spec-set-cell)))

; A 24 by 80 game on the classic set from SEED, each of KEYS taken.
(def spec-game
  (fn (_ seed keys)
    (Heap collect)
    (def g (game-make (spec-set) seed 24 80))
    (List for-each (fn (_ k) (game-key! g k)) keys)
    g))

; The same, with every creature of the level gone: a game to place
; things in.
(def spec-calm
  (fn (_ seed keys)
    (def g (spec-game seed ()))
    (game-creatures! g ())
    (List for-each (fn (_ k) (game-key! g k)) keys)
    g))

; What G draws, row by row, the trailing blanks dropped.
(def spec-screen
  (fn (_ g)
    (def s (game-draw! g (Screen make 24 80)))
    (List map (fn (_ r) (Str8 trim-right (Screen row-text s r))) (List range 0 24))))
(def spec-row (fn (_ g r) (List ref r (spec-screen g))))

; The seeded level, 22 by 80, at DEPTH.
(def spec-level
  (fn (_ seed depth)
    (Heap collect)
    (dungeon-generate (Random sw seed) 22 80 depth (spec-set))))

; F of the level from each of SEEDS at DEPTH, as a list, the heap
; collected between.
(def spec-levels
  (fn (_ seeds depth f) (List map (fn (_ seed) ((fn (_ v) (Heap collect) v) (f (spec-level seed depth)))) seeds)))

; --- placing things ----------------------------------------------------------

; The set's item form named NAME; the creature kind named NAME.
(def spec-item (fn (_ name) (List find (fn (_ f) (str=? (List ref 1 f) name)) (data-all (spec-set) 'item))))
(def spec-creature (fn (_ name) (List find (fn (_ k) (str=? (first k) name)) (data-all (spec-set) 'creature))))

; A new item of the set's NAME put on the floor under the player.
(def spec-drop-here!
  (fn (_ g name)
    (def it (items-new g (spec-item name)))
    (item-at! it (player-r (game-player g)) (player-c (game-player g)))
    (game-floor! g (pair it (game-floor g)))
    it))

; The first of h j k l whose cell is floor with nothing on it, as
; (KEY . (R . C)).
(def spec-open
  (fn (_ g)
    (def p (game-player g))
    (def m (game-map g))
    (def at (fn (_ d) (pair (+ (player-r p) (first (rest d))) (+ (player-c p) (rest (rest d))))))
    (def ok? (fn (_ d) (def c (at d)) (if (= (map-tile m (first c) (rest c)) tile-floor)
                                         (null? (List find (fn (_ cr) (if (= (creature-r cr) (first c)) (= (creature-c cr) (rest c)) #f)) (game-creatures g)))
                                         #f)))
    (def d (List find ok? (list (pair "h" (pair 0 -1)) (pair "j" (pair 1 0)) (pair "k" (pair -1 0)) (pair "l" (pair 0 1)))))
    (pair (first d) (at d))))

; A creature of the set's NAME with HP, awake or not, put at R C.
(def spec-place!
  (fn (_ g name r c hp state)
    (def cr (creature-make (spec-creature name) r c hp state))
    (game-creatures! g (pair cr (game-creatures g)))
    cr))

; KEY pressed until TEST answers true or N presses are spent: the presses.
(def spec-press-until
  (fn (self g key test n)
    (match ((test) 0) ((= n 0) 0) (#t (do (game-key! g key) (+ 1 (self g key test (- n 1))))))))

; How many cells of M are not rock; how many have been seen.
(def %spec-count
  (fn (_ m pred)
    (def n (Vector of 0))
    (List for-each
      (fn (_ r) (List for-each (fn (_ c) (when (pred r c) (Vector set! 0 (+ 1 (Vector ref 0 n)) n))) (List range 0 (map-cols m))))
      (List range 0 (map-rows m)))
    (Vector ref 0 n)))
(def spec-count-open (fn (_ m) (%spec-count m (fn (_ r c) (not (= (map-tile m r c) tile-rock))))))
(def spec-count-seen (fn (_ m) (%spec-count m (fn (_ r c) (map-seen? m r c)))))

; Whether every walkable cell of M can be walked to from the stairs up:
; a flood, a cell a visit, the cells to visit kept as a stack.
(def spec-connected?
  (fn (_ m)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def seen (Vector make (* rows cols) #f))
    (def at (fn (_ r c) (+ (* r cols) c)))
    (def step?
      (fn (_ rr cc)
        (match ((< rr 0) #f) ((< cc 0) #f) ((not (< rr rows)) #f) ((not (< cc cols)) #f)
               ((Vector ref (at rr cc) seen) #f)
               ((not (map-walkable? m rr cc)) #f)
               (#t (do (Vector set! (at rr cc) #t seen) #t)))))
    (def flood
      (fn (self stack)
        (unless (null? stack)
          (do (def r (first (first stack)))
              (def c (rest (first stack)))
              (def next (List filter (fn (_ p) (step? (first p) (rest p)))
                          (list (pair (- r 1) c) (pair (+ r 1) c) (pair r (- c 1)) (pair r (+ c 1)))))
              (self (List append next (rest stack)))))))
    (Vector set! (at (first (map-up m)) (rest (map-up m))) #t seen)
    (flood (list (map-up m)))
    (= 0 (%spec-count m (fn (_ r c) (if (map-walkable? m r c) (not (Vector ref (at r c) seen)) #f))))))
