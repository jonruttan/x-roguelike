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
(import roguelike/base roguelike-version roguelike-main roguelike-options
  data-load data-region data-all data-one data-get data-prop data-prop1 data-trait? data-glyph
  data-choices data-chosen data-choice-text data-choose
  map-rows map-cols map-rooms map-down map-up map-tile map-seen? map-visible? map-walkable? room-lit?
  room-r0 room-c0 room-r1 room-c1 room-centre
  map-room-at map-light-radius! tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up
  dungeon-generate
  game-make game-key! game-explore! game-more! game-score game-score-lines game-score-text game-help game-draw!
  game-set game-depth game-map game-player game-creatures game-creatures! game-floor game-floor! game-pack game-pack!
  game-messages game-turn game-ask game-over game-epitaph game-known game-deepest game-log game-pages-placed
  game-quest-state game-placed game-sure game-traps game-traps! game-exploring?
  game-screen game-screens? game-kept game-kept-level game-hub game-screen-key game-screen-distance game-chain
  game-band band-name game-forms
  game-door game-inside game-level-key game-turn! game-over! game-deepest! game-quest-state!
  game-below? game-region game-top-set
  player-r player-c player-at! player-hp player-hp! player-hpmax player-str player-level player-exp player-gold player-gold!
  player-food player-food! player-condition player-weapon player-armour player-rings
  creature-make creature-r creature-c creature-at! creature-hp creature-hp! creature-state creature-state!
  creature-name creature-glyph creature-trait? creature-carried state-a-kind item-make item-name item-count item-charges item-enchant item-letter item-letter! item-r item-c item-at!
  item-class state-say! state-dist state-adjacent?
  items-name items-new items-known? items-spawn! creatures-kinds creatures-place! trap-make trap-found? chain-where
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

; The set named NAME under data/, read once.
(def %spec-sets (Vector of ()))
(def spec-set-named
  (fn (_ name)
    (def hit (Assoc find name (Vector ref 0 %spec-sets)))
    (if (null? hit)
      ((fn (_ set) (Vector set! 0 (pair (pair name set) (Vector ref 0 %spec-sets)) %spec-sets) set)
       (data-load (Str8 append "data/" name)))
      (rest hit))))

; A 24 by 80 game on SET from SEED, each of KEYS taken.
(def spec-game-on
  (fn (_ set seed keys)
    (Heap collect)
    (def g (game-make set seed 24 80))
    (List for-each (fn (_ k) (game-key! g k)) keys)
    g))

; A 24 by 80 game on the classic set from SEED, each of KEYS taken.
(def spec-game (fn (_ seed keys) (spec-game-on (spec-set) seed keys)))

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

; The seeded level, 22 by 80, at DEPTH, of the classic set or of SET.
(def spec-level-on
  (fn (_ set seed depth)
    (Heap collect)
    (dungeon-generate (Random sw seed) 22 80 depth set)))
(def spec-level (fn (_ seed depth) (spec-level-on (spec-set) seed depth)))

; F of the level from each of SEEDS at DEPTH, as a list, the heap
; collected between.
(def spec-levels
  (fn (_ seeds depth f) (List map (fn (_ seed) ((fn (_ v) (Heap collect) v) (f (spec-level seed depth)))) seeds)))

; --- placing things ----------------------------------------------------------

; G's set's item form named NAME; its creature kind named NAME; its
; trap kind named NAME.
(def spec-item (fn (_ g name) (List find (fn (_ f) (str=? (List ref 1 f) name)) (data-all (game-set g) 'item))))
(def spec-creature (fn (_ g name) (List find (fn (_ k) (str=? (first k) name)) (data-all (game-set g) 'creature))))
(def spec-trap (fn (_ g name) (List find (fn (_ k) (str=? (first k) name)) (data-all (game-set g) 'trap))))

; A new item of the set's NAME put on the floor under the player.
(def spec-drop-here!
  (fn (_ g name)
    (def it (items-new g (spec-item g name)))
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

; The player put on a floor cell beside CR, straight across from it:
; the key that walks into CR.
(def spec-beside!
  (fn (_ g cr)
    (def m (game-map g))
    (def d (List find (fn (_ d) (= (map-tile m (+ (creature-r cr) (first (rest d))) (+ (creature-c cr) (rest (rest d)))) tile-floor))
              (list (pair "j" (pair -1 0)) (pair "k" (pair 1 0)) (pair "l" (pair 0 -1)) (pair "h" (pair 0 1)))))
    (player-at! (game-player g) (+ (creature-r cr) (first (rest d))) (+ (creature-c cr) (rest (rest d))))
    (first d)))

; A creature of the set's NAME with HP, awake or not, put at R C.
(def spec-place!
  (fn (_ g name r c hp state)
    (def cr (creature-make (spec-creature g name) r c hp state))
    (game-creatures! g (pair cr (game-creatures g)))
    cr))

; KEY pressed until TEST answers true or N presses are spent: the presses.
(def spec-press-until
  (fn (self g key test n)
    (match ((test) 0) ((= n 0) 0) (#t (do (game-key! g key) (when (= 0 (% n 10)) (Heap collect)) (+ 1 (self g key test (- n 1))))))))

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

; Whether every walkable cell of M can be walked to from the stairs up,
; or from the first walkable cell on a level without stairs: a flood, a
; cell a visit, the cells to visit kept as a stack.
(def spec-connected?
  (fn (_ m)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def seen (Vector make (* rows cols) #f))
    (def at (fn (_ r c) (+ (* r cols) c)))
    (def start
      (if (null? (map-up m))
        (List find (fn (_ p) (map-walkable? m (first p) (rest p)))
          (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range 0 cols))) (List range 0 rows)))
        (map-up m)))
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
    (Vector set! (at (first start) (rest start)) #t seen)
    (flood (list start))
    (= 0 (%spec-count m (fn (_ r c) (if (map-walkable? m r c) (not (Vector ref (at r c) seen)) #f))))))

; --- invariants --------------------------------------------------------------

; What is wrong with G, drawn on S, as a list of complaints: nobody on
; rock or a wall or on the player, no two creatures on one cell, no dead
; creature left, hit points within the most, every pack item lettered
; once, every floor item placed, and every creature beside the player
; drawn at its cell -- unless it is invisible or the player is blind.
(def spec-invariants
  (fn (_ g s)
    (def m (game-map g))
    (def p (game-player g))
    (def out (Vector of ()))
    (def bad (fn (_ text) (Vector set! 0 (pair text (Vector ref 0 out)) out)))
    (def cell (fn (_ r c) (Str8 sub c 1 (Screen row-text s (+ r 1)))))
    (def looking? (if (null? (game-ask g)) #f (eq? (first (game-ask g)) 'look)))
    (unless (map-walkable? m (player-r p) (player-c p)) (bad "the player stands on rock or a wall"))
    (when (< (player-hpmax p) (player-hp p)) (bad "hit points above the most"))
    (List for-each
      (fn (_ cr)
        (def r (creature-r cr))
        (def c (creature-c cr))
        (unless (map-walkable? m r c) (bad (Str8 append "a " (creature-name cr) " stands on rock or a wall")))
        (when (if (= r (player-r p)) (= c (player-c p)) #f) (bad (Str8 append "a " (creature-name cr) " stands on the player")))
        (when (< (creature-hp cr) 1) (bad (Str8 append "a dead " (creature-name cr) " lingers")))
        (when (< 1 (List count-if (fn (_ x) (if (= (creature-r x) r) (= (creature-c x) c) #f)) (game-creatures g)))
          (bad (Str8 append "two creatures share the " (creature-name cr) "'s cell")))
        (when (if (state-adjacent? r c (player-r p) (player-c p))
                (if (creature-trait? cr 'invisible) #f (if looking? #f (= 0 (player-condition p 'blind)))) #f)
          (unless (str=? (cell r c) (creature-glyph cr))
            (bad (Str8 append "a " (creature-name cr) " beside the player is drawn as '" (cell r c) "'")))))
      (game-creatures g))
    (List for-each
      (fn (_ it)
        (when (null? (item-letter it)) (bad (Str8 append (item-name it) " in the pack has no letter")))
        (when (< 1 (List count-if (fn (_ x) (if (null? (item-letter x)) #f (str=? (item-letter x) (item-letter it)))) (game-pack g)))
          (bad (Str8 append "two pack items are lettered " (item-letter it)))))
      (game-pack g))
    (List for-each (fn (_ it) (when (null? (item-r it)) (bad (Str8 append (item-name it) " on the floor has no cell")))) (game-floor g))
    (List for-each
      (fn (_ text)
        (def struck (spec-striker text))
        (unless (null? struck)
          (unless (List any? (fn (_ cr) (if (str=? (creature-name cr) struck)
                                          (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)) #f))
                             (game-creatures g))
            (bad (Str8 append "a " struck " struck without standing beside the player")))))
      (game-messages g))
    (List reverse (Vector ref 0 out))))

; The creature a blow's message names -- "The NAME hits you." or "The
; NAME misses you." -- or nil for any other message.
(def spec-striker
  (fn (_ text)
    (def tail (fn (_ end) (if (Str8 ends? end text) (Str8 sub 4 (- (Str8 length text) (+ 4 (Str8 length end))) text) ())))
    (match ((not (Str8 starts? "The " text)) ())
           ((not (null? (tail " hits you."))) (tail " hits you."))
           ((not (null? (tail " misses you."))) (tail " misses you."))
           (#t ()))))

; SET played from SEED with N random keys: (SEED DEPTH TURNS OVER
; PROBLEMS), PROBLEMS the first few errors and complaints, each with
; the key and turn.  The screen is drawn and the invariants checked
; every tenth key.
(def spec-random-play
  (fn (_ set seed n)
    (def keys (list "h" "j" "k" "l" "y" "u" "b" "n" "." "." "." "," "i" "q" "r" "z" "e" "w" "W" "T" "P" "R" "d"
                    ">" "<" "o" "?" "L" "a" "b" "c" "d" "e" "y" "n" " " 'escape 'enter))
    (def err-text (fn (_ e) (match ((Err err? e) (e msg)) ((str? e) e) (#t (Err code-of e)))))
    (def rng (Random sw (+ 1000 seed)))
    (def g (spec-game-on set seed ()))
    (def s (Screen make 24 80))
    (def problems (Vector of ()))
    (def note (fn (_ k what) (Vector set! 0 (pair (list (game-turn g) k what) (Vector ref 0 problems)) problems)))
    ((fn (self i)
       (when (if (< i n) (null? (game-over g)) #f)
         (do (def k (rng choice keys))
             (guard (e (note k (err-text e)))
               (do (game-key! g k)
                   (when (= 0 (% i 10))
                     (do (game-draw! g s)
                         (List for-each (fn (_ text) (note k text)) (spec-invariants g s))))))
             (when (= 0 (% i 10)) (Heap collect))
             (self (+ i 1)))))
     0)
    (list seed (game-depth g) (game-turn g) (game-over g) (List take 4 (List reverse (Vector ref 0 problems))))))

; The first of h j k l along which the N cells from the player are
; floor: (KEY . (R . C)) of the Nth, or nil.
(def spec-open-line
  (fn (_ g n)
    (def p (game-player g))
    (def m (game-map g))
    (def floor? (fn (_ d k) (= (map-tile m (+ (player-r p) (* k (first d))) (+ (player-c p) (* k (rest d)))) tile-floor)))
    (def clear? (fn (self d k) (if (< n k) #t (if (floor? d k) (self d (+ k 1)) #f))))
    (def hit (List find (fn (_ x) (clear? (rest x) 1))
               (list (pair "h" (pair 0 -1)) (pair "j" (pair 1 0)) (pair "k" (pair -1 0)) (pair "l" (pair 0 1)))))
    (if (null? hit) ()
      (pair (first hit) (pair (+ (player-r p) (* n (first (rest hit)))) (+ (player-c p) (* n (rest (rest hit)))))))))

; Every question G is asking answered with Escape, a --More-- included,
; so the next key is a move: a crossing's band word can overrun the row.
(def spec-settle!
  (fn (self g) (unless (null? (game-ask g)) (do (game-key! g (lit escape)) (self g)))))
