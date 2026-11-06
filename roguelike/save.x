; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/save.x -- a game kept between sittings, and the scores
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A save is xon, a form a line: the game's numbers, the player, each
; item by its class and name, each creature by its name, the pages
; placed, the level's tiles and seen flags as strings of digits, its
; rooms and stairs.
; Reading one builds the game again on the same set; a thing the set no
; longer has is left out.  A save is read once and then removed by the
; play that read it, so a game is played through once.  The scores are
; lines, best first.

(module roguelike/save)

(import x/type/vector)
(import x/sys/posix)
(import x/sys/file)
(import x/codec/xon)
(import roguelike/data data-all)
(import roguelike/items items-page-named)
(import roguelike/map
  map-make map-rows map-cols map-tile map-set! map-seen? map-seen! map-rooms map-rooms! map-down map-down!
  map-up map-up! map-each! map-light!)
(import roguelike/state
  game-set game-depth game-depth! game-map game-map! game-player game-creatures game-creatures!
  game-floor game-floor! game-pack game-pack! game-turn game-turn! game-known game-known! game-deepest
  game-deepest! game-seed game-guises game-goal-placed? game-goal-placed! game-pages-placed game-page-placed!
  game-new
  player-r player-c player-at! player-hp player-hp! player-hpmax player-hpmax! player-str player-str!
  player-strmax player-strmax! player-level player-level! player-exp player-exp! player-gold player-gold!
  player-armour player-armour! player-weapon player-weapon! player-rings player-rings! player-food
  player-food! player-conditions player-conditions!
  creature-make creature-kind creature-r creature-c creature-hp creature-state creature-carried
  creature-carried! creature-name
  item-make item-form item-class item-name item-count item-charges item-enchant item-letter item-letter!
  item-r item-c item-at! state-say!)

; ~/.x-roguelike/NAME, the directory made.
(def save-path
  (fn (_ name)
    (def home (Sys getenv "HOME"))
    (def dir (Str8 append (if (null? home) "." home) "/.x-roguelike"))
    (unless (File exists? dir) (guard (e ()) (File mkdir dir)))
    (Str8 append dir "/" name)))

; --- writing -----------------------------------------------------------------

(def %sv-item
  (fn (_ head it)
    (list head (symbol->str (item-class it)) (item-name it) (item-count it) (item-charges it) (item-enchant it)
          (if (null? (item-letter it)) "" (item-letter it))
          (if (null? (item-r it)) -1 (item-r it)) (if (null? (item-c it)) -1 (item-c it)))))
(def %sv-digits
  (fn (_ m flag?)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def out (Vector of ()))
    (map-each! 0 0 (- rows 1) (- cols 1)
      (fn (_ r c) (Vector set! 0 (pair (+ 48 (if flag? (if (map-seen? m r c) 1 0) (map-tile m r c))) (Vector ref 0 out)) out)))
    (bytes->str (List reverse (Vector ref 0 out)))))
(def %sv-worn
  (fn (_ p)
    (list (lit worn)
          (if (null? (player-weapon p)) "" (item-letter (player-weapon p)))
          (if (null? (player-armour p)) "" (item-letter (player-armour p)))
          (Str8 join "" (List map item-letter (player-rings p))))))

(def %sv-forms
  (fn (_ g)
    (def p (game-player g))
    (def m (game-map g))
    (List append
      (list (list (lit saved) (game-seed g) (game-depth g) (game-turn g) (game-deepest g) (if (game-goal-placed? g) 1 0))
            (list (lit player) (player-r p) (player-c p) (player-hp p) (player-hpmax p) (player-str p) (player-strmax p)
                  (player-level p) (player-exp p) (player-gold p) (player-food p))
            (pair (lit conditions) (List flat-map (fn (_ c) (list (symbol->str (first c)) (rest c))) (player-conditions p)))
            (pair (lit known) (game-known g))
            (pair (lit pages) (game-pages-placed g))
            (list (lit level) (map-rows m) (map-cols m) (%sv-digits m #f) (%sv-digits m #t))
            (list (lit stairs) (first (map-down m)) (rest (map-down m)) (first (map-up m)) (rest (map-up m))))
      (List map (fn (_ room) (list (lit room) (List ref 0 room) (List ref 1 room) (List ref 2 room) (List ref 3 room) (if (List ref 4 room) 1 0))) (map-rooms m))
      (List map (fn (_ args) (pair (lit guise) (pair (symbol->str (first args)) (rest args)))) (game-guises g))
      (List map (fn (_ it) (%sv-item (lit pack) it)) (game-pack g))
      (list (%sv-worn p))
      (List map (fn (_ it) (%sv-item (lit floor) it)) (game-floor g))
      (List map (fn (_ cr) (list (lit creature) (creature-name cr) (creature-r cr) (creature-c cr) (creature-hp cr)
                                 (symbol->str (creature-state cr))
                                 (if (null? (creature-carried cr)) "" (Str8 append (symbol->str (item-class (creature-carried cr))) "/" (item-name (creature-carried cr))))))
                (game-creatures g)))))

; G written to PATH.
(def save-write! (fn (_ g path) (File write-all path (Xon emit (%sv-forms g)))))

; --- reading -----------------------------------------------------------------

(def %sv-one
  (fn (_ forms head)
    (def hit (List find (fn (_ f) (eq? (first f) head)) forms))
    (if (null? hit) () (rest hit))))
(def %sv-all (fn (_ forms head) (List map rest (List filter (fn (_ f) (eq? (first f) head)) forms))))

; The set's item form of CLASS (a string) and NAME, or nil.
(def %sv-item-form
  (fn (_ set class name)
    (List find (fn (_ f) (if (str=? (symbol->str (first f)) class) (str=? (List ref 1 f) name) #f))
      (data-all set (lit item)))))
(def %sv-item-read
  (fn (_ g set args)
    (def form (match ((str=? (first args) "gold") (list (lit gold) "gold"))
                     ((str=? (first args) "goal") (list (lit goal) (List ref 1 args)))
                     ((str=? (first args) "page") (items-page-named g (List ref 1 args)))
                     (#t (%sv-item-form set (first args) (List ref 1 args)))))
    (if (null? form) ()
      (do (def it (item-make form (List ref 2 args) (List ref 3 args)))
          (Vector set! 3 (List ref 4 args) it)
          (unless (str=? (List ref 5 args) "") (item-letter! it (List ref 5 args)))
          (unless (< (List ref 6 args) 0) (item-at! it (List ref 6 args) (List ref 7 args)))
          it))))
(def %sv-items (fn (_ g set rows) (List reject null? (List map (fn (_ args) (%sv-item-read g set args)) rows))))

(def %sv-digits!
  (fn (_ m text flag?)
    (def cols (map-cols m))
    (map-each! 0 0 (- (map-rows m) 1) (- cols 1)
      (fn (_ r c)
        (def v (- (Char ->int (Str8 ref (+ (* r cols) c) text)) 48))
        (if flag? (when (= v 1) (map-seen! m r c)) (map-set! m r c v))))))

(def %sv-level
  (fn (_ forms)
    (def args (%sv-one forms (lit level)))
    (def m (map-make (List ref 0 args) (List ref 1 args)))
    (%sv-digits! m (List ref 2 args) #f)
    (%sv-digits! m (List ref 3 args) #t)
    (map-rooms! m (List map (fn (_ r) (list (List ref 0 r) (List ref 1 r) (List ref 2 r) (List ref 3 r) (= 1 (List ref 4 r)))) (%sv-all forms (lit room))))
    (def st (%sv-one forms (lit stairs)))
    (map-down! m (pair (List ref 0 st) (List ref 1 st)))
    (map-up! m (pair (List ref 2 st) (List ref 3 st)))
    m))

(def %sv-conditions
  (fn (self l) (if (null? l) () (pair (pair (Str8 ->sym (first l)) (List ref 1 l)) (self (List drop 2 l))))))

(def %sv-by-letter (fn (_ pack l) (if (str=? l "") () (List find (fn (_ it) (str=? (item-letter it) l)) pack))))
(def %sv-rings
  (fn (self pack letters i)
    (if (= i (Str8 length letters)) ()
      ((fn (_ it) (if (null? it) (self pack letters (+ i 1)) (pair it (self pack letters (+ i 1)))))
       (%sv-by-letter pack (Str8 sub i 1 letters))))))

(def %sv-player!
  (fn (_ g forms)
    (def p (game-player g))
    (def a (%sv-one forms (lit player)))
    (player-at! p (List ref 0 a) (List ref 1 a))
    (player-hp! p (List ref 2 a)) (player-hpmax! p (List ref 3 a))
    (player-str! p (List ref 4 a)) (player-strmax! p (List ref 5 a))
    (player-level! p (List ref 6 a)) (player-exp! p (List ref 7 a))
    (player-gold! p (List ref 8 a)) (player-food! p (List ref 9 a))
    (player-conditions! p (%sv-conditions (%sv-one forms (lit conditions))))
    (def worn (%sv-one forms (lit worn)))
    (player-weapon! p (%sv-by-letter (game-pack g) (List ref 0 worn)))
    (player-armour! p (%sv-by-letter (game-pack g) (List ref 1 worn)))
    (player-rings! p (%sv-rings (game-pack g) (List ref 2 worn) 0))))

(def %sv-creature
  (fn (_ g set args)
    (def kind (List find (fn (_ k) (str=? (first k) (first args))) (data-all set (lit creature))))
    (if (null? kind) ()
      (do (def cr (creature-make kind (List ref 1 args) (List ref 2 args) (List ref 3 args) (Str8 ->sym (List ref 4 args))))
          (def carried (List ref 5 args))
          (unless (str=? carried "")
            ((fn (_ at)
               (unless (null? at)
                 (creature-carried! cr (%sv-item-read g set (list (Str8 sub 0 at carried) (Str8 sub (+ at 1) (- (Str8 length carried) (+ at 1)) carried) 1 0 0 "" -1 -1)))))
             (Str8 index-of "/" carried)))
          cr))))

; The game saved at PATH on SET, ROWS by COLS, or nil with none there
; or one that cannot be read.  The guises are the saved game's: the
; game is made with its seed and then given them.
(def save-read
  (fn (_ path set rows cols)
    (if (not (File exists? path)) ()
      (guard (e ())
        (do (def forms (Xon parse (File read-all path)))
            (def head (%sv-one forms (lit saved)))
            (def g (game-new set (List ref 0 head) rows cols))
            (Vector set! 12 (List map (fn (_ a) (pair (Str8 ->sym (first a)) (rest a))) (%sv-all forms (lit guise))) g)
            (game-depth! g (List ref 1 head))
            (game-turn! g (List ref 2 head))
            (game-deepest! g (List ref 3 head))
            (when (= 1 (List ref 4 head)) (game-goal-placed! g))
            (game-known! g (%sv-one forms (lit known)))
            (List for-each (fn (_ name) (game-page-placed! g name)) (List reverse (%sv-one forms (lit pages))))
            (game-map! g (%sv-level forms))
            (game-pack! g (%sv-items g set (%sv-all forms (lit pack))))
            (game-floor! g (%sv-items g set (%sv-all forms (lit floor))))
            (game-creatures! g (List reject null? (List map (fn (_ a) (%sv-creature g set a)) (%sv-all forms (lit creature)))))
            (%sv-player! g forms)
            (map-light! (game-map g) (player-r (game-player g)) (player-c (game-player g)))
            (state-say! g "Welcome back.")
            g)))))

; --- scores ------------------------------------------------------------------

(def %sv-pad (fn (_ n s) (if (< (Str8 length s) n) (Str8 append (Str8 repeat (- n (Str8 length s)) " ") s) s)))
; SCORE kept at PATH: score, level, how it ended.
(def save-score!
  (fn (_ path score depth how)
    (def old (if (File exists? path) (File read-all path) ""))
    (File write-all path (Str8 append old (Str8 str score) " " (Str8 str depth) " " how "\n"))))
(def %sv-score-of (fn (_ line) (def n ((prim-ref (lit convert) (lit to)) (first (Str8 split " " line)) (Type named INTEGER) 10)) n))
(def %sv-insert
  (fn (self line l)
    (match ((null? l) (list line))
           ((< (%sv-score-of (first l)) (%sv-score-of line)) (pair line l))
           (#t (pair (first l) (self line (rest l)))))))
; The scores at PATH, best first, as "SCORE  level N  how", at most ten.
(def save-scores
  (fn (_ path)
    (if (not (File exists? path)) ()
      (List take 10
        (List map (fn (_ line)
                    (def ws (Str8 split " " line))
                    (Str8 append (%sv-pad 6 (first ws)) "  level " (List ref 1 ws) "  " (Str8 join " " (List drop 2 ws))))
          (List fold (fn (_ acc line) (if (str=? line "") acc (%sv-insert line acc))) () (Str8 split "\n" (File read-all path))))))))

(provide roguelike/save save-path save-write! save-read save-score! save-scores)
