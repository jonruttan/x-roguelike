; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/draw.x -- the game on a screen
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The first row says what happened this turn, or asks the question
; being asked; the level fills the rows between; the last row is the
; player's standing.  Cells seen are drawn dim, cells in view plain, in
; the band's (colour N) where the set has bands; items where they were
; seen, creatures only in view, the player last.
; A list being looked at -- the pack, the keys, what someone says --
; lies over the level, and so do the items a question for one can take
; and the choice a question offers.

(module roguelike/draw)

(import x/type/vector)
(import x/tui/style)
(import x/tui/screen Screen screen-put!)
(import roguelike/data data-glyph)
(import x/core/doors str-make)
(import roguelike/map
  map-rows map-cols map-tile map-seen? map-visible? map-down map-up map-row-glyphs! map-visible-next map-visible-run
  tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up)
(import roguelike/state
  game-set game-depth game-map game-player game-creatures game-floor game-pack game-messages game-ask
  game-over game-epitaph game-turn
  player-r player-c player-hp player-hpmax player-str player-strmax player-level player-exp player-gold
  player-food player-condition item-r item-c item-class? item-class creature-r creature-c creature-glyph
  creature-trait? game-param game-band band-prop1 state-defence)
(import roguelike/combat combat-exp-for)
(import roguelike/creatures creatures-shown?)
(import roguelike/items items-glyph items-pack-lines)
(import roguelike/game game-help game-score)

(def %dr-plain 0)
(def %dr-dim (Style make (list (lit dim)) () ()))
(def %dr-bold (Style make (list (lit bold)) () ()))
(def %dr-creature (Style make (list (lit bold)) 3 ()))
(def %dr-talker (Style make (list (lit bold)) 7 ()))
(def %dr-item (Style make () 6 ()))
(def %dr-gold (Style make (list (lit bold)) 3 ()))
(def %dr-goal (Style make (list (lit bold)) 5 ()))
(def %dr-stairs (Style make (list (lit bold)) 2 ()))
(def %dr-ask (Style make (list (lit bold)) () ()))

; The set's glyph of each tile code, as a byte, in a vector by code:
; rock is a blank.
(def %dr-tile-names
  (list (pair tile-floor (lit floor)) (pair tile-wall (lit wall)) (pair tile-door (lit door))
        (pair tile-passage (lit passage)) (pair tile-down (lit down)) (pair tile-up (lit up))))
(def %dr-tile-bytes
  (fn (_ set)
    (def v (Vector make 7 32))
    (List for-each (fn (_ p) (Vector set! (first p) (Char ->int (Str8 ref 0 (data-glyph set (rest p) "?"))) v)) %dr-tile-names)
    v))

; Row R drawn: every seen cell's glyph as one dim text, a blank for the
; rest, so the row is written whole even with nothing seen and nothing
; laid over it last time stays; each run of cells in view put again
; plain.  DIM and PLAIN are the level's styles.
(def %dr-row!
  (fn (_ s m r bytes buf dim plain)
    (def cols (map-cols m))
    (map-row-glyphs! m r bytes buf)
    (screen-put! s (+ r 1) 0 buf dim)
    ((fn (self c)
       (when (< c cols)
         ((fn (_ e) (screen-put! s (+ r 1) c (Str8 sub c (- e c) buf) plain) (self (map-visible-next m r e)))
          (map-visible-run m r c))))
     (map-visible-next m r 0))))

; The tile bytes and the item glyphs of a set, made once and kept
; against the set they were made from; the band's styles, (COLOUR DIM
; . PLAIN), kept against its colour.
(def %dr-cache (Vector of () () () ()))
(def %dr-band-styles
  (fn (_ g)
    (def b (game-band g))
    (def colour (if (null? b) () (band-prop1 b (lit colour) ())))
    (def kept (Vector ref 3 %dr-cache))
    (match ((null? colour) (pair %dr-dim %dr-plain))
           ((if (null? kept) #f (= (first kept) colour)) (rest kept))
           (#t (do (Vector set! 3 (pair colour (pair (Style make (list (lit dim)) colour ()) (Style make () colour ()))) %dr-cache)
                   (rest (Vector ref 3 %dr-cache)))))))
(def %dr-cached!
  (fn (_ set)
    (unless (same? set (Vector ref 0 %dr-cache))
      (do (Vector set! 0 set %dr-cache)
          (Vector set! 1 (%dr-tile-bytes set) %dr-cache)
          (Vector set! 2 (List map (fn (_ c) (pair c (data-glyph set c "?")))
                                   (list (lit potion) (lit scroll) (lit wand) (lit ring) (lit weapon) (lit armour)
                                         (lit food) (lit gold) (lit goal) (lit page) (lit token)))
                       %dr-cache)))))
(def %dr-item-glyph
  (fn (self it l)
    (match ((null? l) "?") ((eq? (first (first l)) (item-class it)) (rest (first l))) (#t (self it (rest l))))))
(def %dr-stairs!
  (fn (_ s m at bytes t)
    (when (map-visible? m (first at) (rest at))
      (screen-put! s (+ (first at) 1) (rest at) (bytes->str (list (Vector ref t bytes))) %dr-stairs))))
(def %dr-map!
  (fn (_ g s set m)
    (%dr-cached! set)
    (def bytes (Vector ref 1 %dr-cache))
    (def buf (str-make (map-cols m)))
    (def styles (%dr-band-styles g))
    ((fn (self r) (when (< r (map-rows m)) (do (%dr-row! s m r bytes buf (first styles) (rest styles)) (self (+ r 1))))) 0)
    (%dr-stairs! s m (map-down m) bytes tile-down)
    (%dr-stairs! s m (map-up m) bytes tile-up)))

(def %dr-item-style
  (fn (_ it) (match ((item-class? it (lit gold)) %dr-gold) ((item-class? it (lit goal)) %dr-goal) (#t %dr-item))))
(def %dr-items!
  (fn (_ g s)
    (def m (game-map g))
    (List for-each
      (fn (_ it) (when (map-seen? m (item-r it) (item-c it))
                   (screen-put! s (+ (item-r it) 1) (item-c it) (%dr-item-glyph it (Vector ref 2 %dr-cache)) (%dr-item-style it))))
      (game-floor g))))
(def %dr-creatures!
  (fn (_ g s)
    (List for-each
      (fn (_ cr) (when (creatures-shown? g cr)
                   (screen-put! s (+ (creature-r cr) 1) (creature-c cr) (creature-glyph cr)
                     (if (creature-trait? cr (lit talks)) %dr-talker %dr-creature))))
      (game-creatures g))))
(def %dr-player!
  (fn (_ g s)
    (def p (game-player g))
    (screen-put! s (+ (player-r p) 1) (player-c p) (data-glyph (game-set g) (lit player) "@") %dr-bold)
    (Screen cursor s (+ (player-r p) 1) (player-c p))))

; --- the rows above and below -----------------------------------------------

(def %dr-hunger
  (fn (_ g)
    (def f (player-food (game-player g)))
    (def spec (game-param g (lit hunger) (list 1300 300 150)))
    (match ((< (List ref 0 spec) 1) "") ((< f 1) "Fainting") ((< f (+ (List ref 2 spec) 1)) "Weak") ((< f (+ (List ref 1 spec) 1)) "Hungry") (#t ""))))
(def %dr-conditions
  (fn (_ g)
    (def p (game-player g))
    (Str8 join " " (List filter (fn (_ s) (not (str=? s "")))
                     (List map (fn (_ c) (if (< 0 (player-condition p (first c))) (rest c) ""))
                               (list (pair (lit confused) "Confused") (pair (lit blind) "Blind") (pair (lit held) "Held")
                                     (pair (lit hasted) "Quick") (pair (lit slowed) "Slow") (pair (lit seeing) "Seeing")))))))
(def %dr-status
  (fn (_ g)
    (def p (game-player g))
    (Str8 append
      "Level:" (Str8 str (game-depth g)) "  Gold:" (Str8 str (player-gold p))
      "  Hp:" (Str8 str (player-hp p)) "(" (Str8 str (player-hpmax p)) ")"
      "  Str:" (Str8 str (player-str p)) "(" (Str8 str (player-strmax p)) ")"
      "  Arm:" (Str8 str (state-defence g))
      "  Exp:" (Str8 str (player-level p)) "/" (Str8 str (player-exp p))
      "  " (%dr-hunger g) " " (%dr-conditions g))))

(def %dr-top
  (fn (_ g)
    (def q (game-ask g))
    (match
      ((if (null? q) #f (eq? (first q) (lit more))) (Str8 append (Str8 join "  " (game-messages g)) "  --More--"))
      ((not (null? q)) (if (eq? (first q) (lit look)) (Str8 append (List ref 1 q) "  --any key--") (List ref 1 q)))
      ((not (null? (game-over g)))
        (Str8 append (Str8 join "  " (game-messages g)) "  --any key--"))
      (#t (Str8 join "  " (game-messages g))))))

(def %dr-lines!
  (fn (self s r lines)
    (unless (null? lines)
      (do (Screen fill s r 0 (+ 2 (Str8 length (first lines))) %dr-plain)
          (screen-put! s r 1 (first lines) %dr-plain)
          (self s (+ r 1) (rest lines))))))
; A list looked at, or the pack's items a question can take, over the
; level.
(def %dr-overlay!
  (fn (_ g s)
    (def q (game-ask g))
    (match ((null? q) ())
           ((eq? (first q) (lit look)) (%dr-lines! s 1 (List ref 3 q)))
           ((eq? (first q) (lit choose)) (%dr-lines! s 1 (List ref 3 q)))
           ((eq? (first q) (lit item)) (%dr-lines! s 1 (items-pack-lines g (List ref 3 q))))
           (#t ()))))

; G drawn on S: S.  The level's rows are written whole; the first and
; last rows are blanked before their text.
(def game-draw!
  (fn (_ g s)
    (Screen fill s 0 0 (Screen cols s) %dr-plain)
    (Screen fill s (- (Screen rows s) 1) 0 (Screen cols s) %dr-plain)
    (%dr-map! g s (game-set g) (game-map g))
    (%dr-items! g s)
    (%dr-creatures! g s)
    (%dr-player! g s)
    (%dr-overlay! g s)
    (screen-put! s 0 0 (%dr-top g) (if (null? (game-ask g)) %dr-plain %dr-ask))
    (screen-put! s (- (Screen rows s) 1) 0 (%dr-status g) %dr-plain)
    s))

(provide roguelike/draw game-draw!)
