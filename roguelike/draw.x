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
; player's standing.  Cells seen are drawn dim, cells in view plain;
; items where they were seen, creatures only in view, the player last.
; A list being looked at -- the pack, the keys -- lies over the level.

(module roguelike/draw)

(import x/type/vector)
(import x/tui/style)
(import x/tui/screen Screen screen-put!)
(import roguelike/data data-glyph)
(import roguelike/map
  map-rows map-cols map-tile map-seen? map-visible? tile-rock tile-floor tile-wall tile-door tile-passage
  tile-down tile-up)
(import roguelike/state
  game-set game-depth game-map game-player game-creatures game-floor game-pack game-messages game-ask
  game-over game-epitaph game-turn
  player-r player-c player-hp player-hpmax player-str player-strmax player-level player-exp player-gold
  player-food player-condition item-r item-c item-class? item-class creature-r creature-c creature-glyph
  game-param state-defence)
(import roguelike/combat combat-exp-for)
(import roguelike/creatures creatures-shown?)
(import roguelike/items items-glyph)
(import roguelike/game game-help game-score)

(def %dr-plain 0)
(def %dr-dim (Style make (list (lit dim)) () ()))
(def %dr-bold (Style make (list (lit bold)) () ()))
(def %dr-creature (Style make (list (lit bold)) 3 ()))
(def %dr-item (Style make () 6 ()))
(def %dr-gold (Style make (list (lit bold)) 3 ()))
(def %dr-goal (Style make (list (lit bold)) 5 ()))
(def %dr-stairs (Style make (list (lit bold)) 2 ()))
(def %dr-ask (Style make (list (lit bold)) () ()))

; The set's glyph for tile T.
(def %dr-tile-names
  (list (pair tile-floor (lit floor)) (pair tile-wall (lit wall)) (pair tile-door (lit door))
        (pair tile-passage (lit passage)) (pair tile-down (lit down)) (pair tile-up (lit up))))
(def %dr-tile-glyph
  (fn (_ set t)
    (def name (Assoc get t %dr-tile-names))
    (if (null? name) " " (data-glyph set name "?"))))

(def %dr-cell!
  (fn (_ g s set m r c)
    (def t (map-tile m r c))
    (match
      ((= t tile-rock) ())
      ((map-visible? m r c)
        (screen-put! s (+ r 1) c (%dr-tile-glyph set t)
          (match ((= t tile-down) %dr-stairs) ((= t tile-up) %dr-stairs) (#t %dr-plain))))
      ((map-seen? m r c) (screen-put! s (+ r 1) c (%dr-tile-glyph set t) %dr-dim))
      (#t ()))))
(def %dr-row!
  (fn (self g s set m r c)
    (when (< c (map-cols m)) (do (%dr-cell! g s set m r c) (self g s set m r (+ c 1))))))
(def %dr-map!
  (fn (self g s set m r)
    (when (< r (map-rows m)) (do (%dr-row! g s set m r 0) (self g s set m (+ r 1))))))

(def %dr-item-style
  (fn (_ it) (match ((item-class? it (lit gold)) %dr-gold) ((item-class? it (lit goal)) %dr-goal) (#t %dr-item))))
(def %dr-items!
  (fn (_ g s)
    (def m (game-map g))
    (List for-each
      (fn (_ it) (when (map-seen? m (item-r it) (item-c it))
                   (screen-put! s (+ (item-r it) 1) (item-c it) (items-glyph g it) (%dr-item-style it))))
      (game-floor g))))
(def %dr-creatures!
  (fn (_ g s)
    (List for-each
      (fn (_ cr) (when (creatures-shown? g cr)
                   (screen-put! s (+ (creature-r cr) 1) (creature-c cr) (creature-glyph cr) %dr-creature)))
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
    (match ((< f 1) "Fainting") ((< f (+ (List ref 2 spec) 1)) "Weak") ((< f (+ (List ref 1 spec) 1)) "Hungry") (#t ""))))
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
(def %dr-overlay!
  (fn (_ g s)
    (def q (game-ask g))
    (when (if (null? q) #f (eq? (first q) (lit look)))
      (%dr-lines! s 1 (List ref 3 q)))))

; G drawn on S: S.
(def game-draw!
  (fn (_ g s)
    (Screen clear s)
    (%dr-map! g s (game-set g) (game-map g) 0)
    (%dr-items! g s)
    (%dr-creatures! g s)
    (%dr-player! g s)
    (%dr-overlay! g s)
    (screen-put! s 0 0 (%dr-top g) (if (null? (game-ask g)) %dr-plain %dr-ask))
    (screen-put! s (- (Screen rows s) 1) 0 (%dr-status g) %dr-plain)
    s))

(provide roguelike/draw game-draw!)
