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
; player's standing, headed by the level, or the screen in a world of
; screens.  Cells seen are drawn dim, cells in view plain, in
; the band's (colour N) where the set has bands, or in the colour the
; set gives the cell's kind of terrain; found traps and items
; where they were seen, creatures only in view, the player last.
; A list being looked at -- the pack, the keys, what someone says --
; lies over the level, and so do the items a question for one can take
; and the choice a question offers.

(module roguelike/draw)

(import x/type/vector)
(import x/tui/style)
(import x/tui/screen Screen screen-put!)
(import roguelike/data data-glyph)
(import x/core/doors str-make int& int>>)
(import roguelike/map
  map-rows map-cols map-tile map-seen? map-visible? map-down map-up map-row-glyphs! map-visible-next map-visible-run
  map-terrain map-kinds map-look map-look-run tile-down tile-up)
(import roguelike/state
  game-set game-depth game-map game-player game-creatures game-floor game-pack game-messages game-ask
  game-over game-epitaph game-turn game-traps game-param1 game-screens? game-screen
  player-r player-c player-hp player-hpmax player-str player-strmax player-level player-exp player-gold
  player-food player-condition item-r item-c item-class? item-class creature-r creature-c creature-glyph
  creature-trait? game-param game-band band-prop1 game-forms state-defence band-name game-screen-name)
(import roguelike/combat combat-exp-for)
(import roguelike/creatures creatures-shown?)
(import roguelike/items items-glyph items-pack-lines)
(import roguelike/traps trap-r trap-c trap-found?)
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
(def %dr-trap (Style make (list (lit bold)) 1 ()))
(def %dr-ask (Style make (list (lit bold)) () ()))

; --- terrain's look -----------------------------------------------------------

; The terminal's look for a kind of terrain: the set's (glyph KIND "g")
; and (colour KIND N), each from the band's forms before the set's.  A
; kind the set gives no glyph has the glyph here, and failing that the
; glyph of the kind it is a sort of; rock is a blank.
(def %dr-glyphs
  (list (pair (lit water) "~") (pair (lit fall) ";") (pair (lit hedge) "\"") (pair (lit gate) "+")
        (pair (lit thicket) "T") (pair (lit bog) ",")))
(def %dr-named (fn (self name l) (if (eq? (List ref 1 (first l)) name) (first l) (self name (rest l)))))
(def %dr-glyph
  (fn (self forms t)
    (def name (List ref 1 t))
    (def given (data-glyph forms name ()))
    (def mine (List find (fn (_ p) (eq? (first p) name)) %dr-glyphs))
    (match ((eq? name (lit rock)) " ")
           ((not (null? given)) given)
           ((not (null? mine)) (rest mine))
           ((null? (List ref 2 t)) "?")
           (#t (self forms (%dr-named (List ref 2 t) map-terrain))))))
; Each kind's glyph, as a byte, in a vector by code.
(def %dr-tile-bytes
  (fn (_ forms)
    (def v (Vector make map-kinds 32))
    (List for-each (fn (_ t) (Vector set! (first t) (Char ->int (Str8 ref 0 (%dr-glyph forms t))) v)) map-terrain)
    v))
; The colour FORMS give a kind NAME, (colour NAME N), or nil; a band's
; own (colour N) is not one.
(def %dr-colour
  (fn (self forms name)
    (match ((null? forms) ())
           ((if (pair? (first forms))
              (if (eq? (first (first forms)) (lit colour))
                (if (pair? (rest (rest (first forms)))) (eq? (List ref 1 (first forms)) name) #f)
                #f)
              #f)
             (List ref 2 (first forms)))
           (#t (self (rest forms) name)))))
; The kinds' looks: (CLASSES . STYLES), CLASSES a vector by code of
; each kind's class, 0 for none of its own; STYLES a vector by class of
; its (DIM . PLAIN).  A kind with no colour takes the colour of the kind
; it is a sort of.
(def %dr-classes
  (fn (_ forms)
    (def colour-of
      (fn (self t)
        (def given (%dr-colour forms (List ref 1 t)))
        (match ((not (null? given)) given) ((null? (List ref 2 t)) ()) (#t (self (%dr-named (List ref 2 t) map-terrain))))))
    (def classes (Vector make map-kinds 0))
    (def styles (Vector make (+ map-kinds 1) ()))
    (List for-each
      (fn (_ t)
        (def colour (colour-of t))
        (unless (null? colour)
          (do (Vector set! (first t) (+ (first t) 1) classes)
              (Vector set! (+ (first t) 1) (pair (Style make (list (lit dim)) colour ()) (Style make () colour ())) styles))))
      map-terrain)
    (pair classes styles)))

; Row R drawn: every seen cell's glyph as one dim text, a blank for the
; rest, so the row is written whole even with nothing seen and nothing
; laid over it last time stays; each run of cells in view put again
; plain.  DIM and PLAIN are the level's styles.  LOOKS, (CLASSES .
; STYLES) or nil, are the kinds with colours of their own: each run of
; cells of one of those put again in its colour, dim or plain.
(def %dr-row!
  (fn (_ s m r bytes buf dim plain looks)
    (def cols (map-cols m))
    (map-row-glyphs! m r bytes buf)
    (screen-put! s (+ r 1) 0 buf dim)
    ((fn (self c)
       (when (< c cols)
         ((fn (_ e) (screen-put! s (+ r 1) c (Str8 sub c (- e c) buf) plain) (self (map-visible-next m r e)))
          (map-visible-run m r c))))
     (map-visible-next m r 0))
    (unless (null? looks)
      ((fn (self c)
         (when (< c cols)
           (do (def k (map-look m r c (first looks)))
               (def e (map-look-run m r c (first looks)))
               (when (< 1 k)
                 ((fn (_ st) (screen-put! s (+ r 1) c (Str8 sub c (- e c) buf) (if (= (int& k 1) 1) (rest st) (first st))))
                  (Vector ref (int>> k 1) (rest looks))))
               (self e))))
       0))))

; The tile bytes, the item glyphs and the terrain's looks of the
; level's forms, its band's in front of the set's, made once and kept
; against the set and the band they were made from; the band's styles,
; (COLOUR DIM . PLAIN), kept against its colour.
(def %dr-cache (Vector of () () () () () ()))
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
  (fn (_ g)
    (def b (game-band g))
    (unless (if (same? (game-set g) (Vector ref 0 %dr-cache)) (same? b (Vector ref 4 %dr-cache)) #f)
      (do (def forms (game-forms g))
          (Vector set! 0 (game-set g) %dr-cache)
          (Vector set! 4 b %dr-cache)
          (Vector set! 1 (%dr-tile-bytes forms) %dr-cache)
          (Vector set! 5 ((fn (_ looks) (if (List any? (fn (_ t) (< 0 (Vector ref (first t) (first looks)))) map-terrain) looks ()))
                          (%dr-classes forms))
                       %dr-cache)
          (Vector set! 2 (List map (fn (_ c) (pair c (data-glyph forms c "?")))
                                   (list (lit potion) (lit scroll) (lit wand) (lit ring) (lit weapon) (lit armour)
                                         (lit food) (lit gold) (lit goal) (lit page) (lit token)))
                       %dr-cache)))))
(def %dr-item-glyph
  (fn (self it l)
    (match ((null? l) "?") ((eq? (first (first l)) (item-class it)) (rest (first l))) (#t (self it (rest l))))))
(def %dr-stairs!
  (fn (_ s m at bytes t)
    (when (if (null? at) #f (map-visible? m (first at) (rest at)))
      (screen-put! s (+ (first at) 1) (rest at) (bytes->str (list (Vector ref t bytes))) %dr-stairs))))
(def %dr-map!
  (fn (_ g s m)
    (%dr-cached! g)
    (def bytes (Vector ref 1 %dr-cache))
    (def buf (str-make (map-cols m)))
    (def styles (%dr-band-styles g))
    (def looks (Vector ref 5 %dr-cache))
    ((fn (self r) (when (< r (map-rows m)) (do (%dr-row! s m r bytes buf (first styles) (rest styles) looks) (self (+ r 1))))) 0)
    (%dr-stairs! s m (map-down m) bytes tile-down)
    (%dr-stairs! s m (map-up m) bytes tile-up)))

(def %dr-traps!
  (fn (_ g s)
    (def m (game-map g))
    (def glyph (data-glyph (game-set g) (lit trap) "^"))
    (List for-each
      (fn (_ t) (when (if (trap-found? t) (map-seen? m (trap-r t) (trap-c t)) #f)
                  (screen-put! s (+ (trap-r t) 1) (trap-c t) glyph %dr-trap)))
      (game-traps g))))
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
    (match ((< (List ref 0 spec) 1) "")
           ((< f 1) (if (< 0 (game-param1 g (lit starve) 0)) "Starving" "Fainting"))
           ((< f (+ (List ref 2 spec) 1)) "Weak")
           ((< f (+ (List ref 1 spec) 1)) "Hungry")
           (#t ""))))
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
      (if (game-screens? g)
        (Str8 append "Screen:" (Str8 str (first (game-screen g))) "," (Str8 str (rest (game-screen g))))
        (Str8 append "Level:" (Str8 str (game-depth g))))
      "  Gold:" (Str8 str (player-gold p))
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
; The lines laid over the level: a list looked at, a choice, or the
; pack's items a question can take; nil for none.  The window lays the
; same lines on a panel.
(def draw-overlay
  (fn (_ g)
    (def q (game-ask g))
    (match ((null? q) ())
           ((eq? (first q) (lit look)) (List ref 3 q))
           ((eq? (first q) (lit choose)) (List ref 3 q))
           ((eq? (first q) (lit item)) (items-pack-lines g (List ref 3 q)))
           (#t ()))))
(def %dr-overlay! (fn (_ g s) (%dr-lines! s 1 (draw-overlay g))))

; G drawn on S: S.  The level's rows are written whole; the first and
; last rows are blanked before their text.
(def game-draw!
  (fn (_ g s)
    (Screen fill s 0 0 (Screen cols s) %dr-plain)
    (Screen fill s (- (Screen rows s) 1) 0 (Screen cols s) %dr-plain)
    (%dr-map! g s (game-map g))
    (%dr-traps! g s)
    (%dr-items! g s)
    (%dr-creatures! g s)
    (%dr-player! g s)
    (%dr-overlay! g s)
    (screen-put! s 0 0 (%dr-top g) (if (null? (game-ask g)) %dr-plain %dr-ask))
    (screen-put! s (- (Screen rows s) 1) 0 (%dr-status g) %dr-plain)
    s))

; The top row's text and the standing's, as the terminal shows them;
; the window draws them too.
(def draw-top (fn (_ g) (%dr-top g)))
(def draw-status (fn (_ g) (%dr-status g)))

; The standing in its parts, for a front-end that lays it out itself:
; (PLACE DEPTH HP HPMAX GOLD STR STRMAX ARMOUR LEVEL WARNINGS).  PLACE is
; the screen's name in a world of screens, else the band's, or ""; DEPTH
; the level, nil in a world of screens; WARNINGS hunger and conditions,
; "" for none.
(def draw-standing
  (fn (_ g)
    (def p (game-player g))
    (def b (game-band g))
    (list (if (game-screens? g) (game-screen-name g) (if (null? b) "" (band-name b)))
          (if (game-screens? g) () (game-depth g))
          (player-hp p) (player-hpmax p) (player-gold p) (player-str p) (player-strmax p)
          (state-defence g) (player-level p)
          (Str8 join " " (List filter (fn (_ s) (not (str=? s ""))) (list (%dr-hunger g) (%dr-conditions g)))))))

(provide roguelike/draw game-draw! draw-top draw-status draw-standing draw-overlay)
