; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/chain.x -- an errand made from the set's scenes
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A set's (scene NAME GIVER . PROPS) is a link an errand may use: the
; GIVER creature, one that talks, who (wants "thing") and, given it,
; (gives CLASS "name"), or (gives goal), the goal itself; and its (ask
; LINE ...), (again ...) and (done ...) lines, in which {want} is the
; thing wanted and {where} the way to it from the giver's screen.  A
; game's chain is walked back from the goal: a scene that gives it
; stands on the hub; what it wants, some other scene gives, or none
; does and it lies on the ground a screen farther out, or in the
; keeping of the token's (carrier "kind"); each link stands a screen
; farther from the hub than the one before, and the chain is (chain LO
; HI) links at most.  Every link becomes a (quest ...) form kept in the
; game and read with the set's own.  A set without scenes, or without
; a world of screens, has no chain.

(module roguelike/chain)

(import roguelike/data data-all data-prop data-prop1)
(import roguelike/state
  game-rng game-set game-chain! game-hub game-world-cols game-world-rows game-screen-distance game-param
  game-screens? state-roll state-fill)

(def %ch-giver (fn (_ s) (List ref 1 s)))
(def %ch-wants (fn (_ s) (data-prop1 s (lit wants) "")))
(def %ch-gives (fn (_ s) (data-prop s (lit gives) ())))
; Whether scene S gives the thing named NAME; whether it gives the goal.
(def %ch-gives?
  (fn (_ s name) (def gv (%ch-gives s)) (if (< (List length gv) 2) #f (str=? (List ref 1 gv) name))))
(def %ch-gives-goal? (fn (_ s) (def gv (%ch-gives s)) (if (null? gv) #f (eq? (first gv) (lit goal)))))

; --- the way to a screen ------------------------------------------------------

(def %ch-abs (fn (_ n) (if (< n 0) (- 0 n) n)))
(def %ch-words (list "one" "two" "three" "four" "five" "six" "seven" "eight" "nine"))
(def %ch-count (fn (_ n) (if (< n 10) (List ref (- n 1) %ch-words) (Str8 str n))))
; N screens along an axis, FAR the way for a positive N, NEAR for a
; negative one; "" for none.
(def %ch-leg
  (fn (_ n far near)
    (if (= n 0) ""
      (Str8 append (%ch-count (%ch-abs n)) (if (= (%ch-abs n) 1) " screen " " screens ") (if (< n 0) near far)))))
; The way from screen FROM to screen TO, (X . Y) each, in words: "two
; screens east and one screen north", or "here, on this screen".
(def chain-where
  (fn (_ from to)
    (def legs (List reject (fn (_ s) (str=? s ""))
                (list (%ch-leg (- (first to) (first from)) "east" "west") (%ch-leg (- (rest to) (rest from)) "south" "north"))))
    (if (null? legs) "here, on this screen" (Str8 join " and " legs))))

; --- the walk -----------------------------------------------------------------

; The links, hub first: SCENE, then a scene not among the USED names
; that gives what it wants, and so on, until none does or N stand.
(def %ch-walk
  (fn (self g scenes scene used n)
    (def cands (List filter (fn (_ s) (if (List includes? (first s) used) #f (%ch-gives? s (%ch-wants scene)))) scenes))
    (if (if (null? cands) #t (not (< (List length used) n))) (list scene)
      (pair scene (self g scenes ((game-rng g) choice cands) (pair (first scene) used) n)))))

(def %ch-same? (fn (_ a b) (if (= (first a) (first b)) (= (rest a) (rest b)) #f)))
; The screens at distance D from the hub not among USED, or, with none
; left there, nearer in, never the hub.
(def %ch-ring
  (fn (self g d used)
    (def all (List flat-map (fn (_ y) (List map (fn (_ x) (pair x y)) (List range 0 (game-world-cols g))))
                            (List range 0 (game-world-rows g))))
    (def ring (List filter (fn (_ p) (if (= (game-screen-distance g (first p) (rest p)) d)
                                       (not (List any? (fn (_ u) (%ch-same? u p)) used)) #f))
                all))
    (match ((not (null? ring)) ring) ((< d 2) ()) (#t (self g (- d 1) used)))))
; N screens drawn one at each distance from D outward, none twice.
(def %ch-screens
  (fn (self g n d used)
    (if (< n 1) ()
      ((fn (_ ring)
         (def at (if (null? ring) (game-hub g) ((game-rng g) choice ring)))
         (pair at (self g (- n 1) (+ d 1) (pair at used))))
       (%ch-ring g d used)))))

; --- the quests ---------------------------------------------------------------

; The set's token item named NAME, or nil.
(def %ch-token
  (fn (_ g name)
    (List find (fn (_ f) (if (eq? (first f) (lit token)) (str=? (List ref 1 f) name) #f)) (data-all (game-set g) (lit item)))))

; Link SCENE on screen AT, what it wants on screen NEXT, as a quest
; form; FIND? when the want lies there rather than being given.
(def %ch-quest
  (fn (_ g scene at next find?)
    (def want (%ch-wants scene))
    (def subs (list (pair "want" want) (pair "where" (chain-where at next))))
    (def lines (fn (_ key) (pair key (List map (fn (_ l) (state-fill l subs)) (data-prop scene key ())))))
    (def gives (%ch-gives scene))
    (def reward (if (eq? (first gives) (lit goal)) (list (lit goal) (first (game-param g (lit goal) (list "the prize" "*")))) gives))
    (def token (%ch-token g want))
    (def carrier (if (null? token) () (data-prop token (lit carrier) ())))
    (List append
      (list (lit quest) (first scene) (%ch-giver scene)
            (list (lit screen) (first at) (rest at)) (list (lit wants) (lit bring) want))
      (if find? (list (list (lit lies) (first next) (rest next))) ())
      (if (if find? (not (null? carrier)) #f) (list (pair (lit carrier) carrier)) ())
      (list (lines (lit ask)) (lines (lit again)) (lines (lit done)) (list (lit rewards) reward)))))

; G's chain drawn from its set's scenes: a scene giving the goal on the
; hub, each link a screen farther out, the last link's want lying a
; screen beyond it.
(def chain-build!
  (fn (_ g)
    (def scenes (data-all (game-set g) (lit scene)))
    (def starts (List filter %ch-gives-goal? scenes))
    (unless (if (null? starts) #t (not (game-screens? g)))
      (do (def range (game-param g (lit chain) (list 2 4)))
          (def start ((game-rng g) choice starts))
          (def links (%ch-walk g scenes start (list (first start)) (state-roll (game-rng g) (first range) (List ref 1 range))))
          (def screens (pair (game-hub g) (%ch-screens g (List length links) 1 (list (game-hub g)))))
          (def last (- (List length links) 1))
          (game-chain! g
            (List map (fn (_ i) (%ch-quest g (List ref i links) (List ref i screens) (List ref (+ i 1) screens) (= i last)))
                      (List range 0 (List length links))))))))

(provide roguelike/chain chain-build! chain-where)
