; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/game.x -- a game played: the keys, the turns, the levels
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A key is a move, an attack on what stands there, or a command.  A
; command that needs an answer -- which thing, which way, really? --
; asks, and the next key answers it.  Every turn taken, the creatures
; take theirs, hunger grows, hit points return, and the view is lit
; again.  With the set's (starve N), hunger past nothing costs a hit
; point every N turns and stops the hit points returning, in place of
; the faint and the end.  Exploring, o, is a step a turn: the key takes
; the first, and whoever drives the game takes the rest with
; game-explore! until it answers that the walk is over, drawing each;
; any key stops it.  The stairs down make a new level; the stairs up are sealed
; until the goal is held, and then each level climbed is made anew,
; roused and hostile.  A set's bands each say their (enter "TEXT") on
; their first level and put their (guardian "NAME") by the stairs down
; on their last, which stay shut while it lives.  Walking into a
; creature that talks is a word with it, not a blow.  In a world of
; screens, (world screens W H), there are no stairs: a step off the
; edge of the screen is a step onto the next, each screen's level kept
; and taken up again, m shows the screens visited, and the hub with
; the goal in hand is the win; a door on a screen, > on it, goes into
; the interior behind it (see interiors.x), kept the same way, and its
; way out, <, comes back onto the door.  An interior that is (below
; NAME) goes down into the region NAME instead, a descent by that set's
; own forms, whose way up out of its first level, never sealed, comes
; back onto the door.  Nothing here touches a terminal: a spec gives
; keys and reads the state.

(module roguelike/game)

(import x/type/vector)
(import x/sys/gc)
(import roguelike/map
  map-rows map-cols map-in? map-tile map-up map-down map-walkable? map-seen? map-light! map-light-radius!
  map-place-at tile-rock tile-down tile-up tile-door)
(import roguelike/dungeon dungeon-generate dungeon-spot)
(import x/core/doors int/)
(import roguelike/state
  game-rng game-set game-depth game-depth! game-map game-map! game-player game-creatures game-creatures!
  game-floor game-floor! game-pack game-turn game-turn! game-ask game-ask! game-over game-over! game-traps game-traps! game-told game-told! game-clock game-clock!
  game-exploring game-exploring! game-below? game-go-below! game-go-above! game-top-set
  game-screen game-screen! game-kept-level game-keep! game-screens? game-world-cols game-world-rows game-hub
  game-screen-distance game-screen-in? game-screen-key game-door game-inside game-inside! game-level-key
  game-screen-form game-screen-name game-regions game-region game-home game-place
  game-deepest game-deepest! game-rows game-cols game-param game-param1 game-new game-epitaph! game-kept game-quests
  game-messages game-messages! game-log game-band game-band-from band-to band-prop1 game-forms
  player-r player-c player-at! player-hp player-hp! player-hpmax player-level player-food player-food! player-lamp player-lamp!
  player-condition player-tick! player-armour player-rings player-gold
  state-say! state-tell! state-text state-clear-messages! state-clear-log! state-roll state-chance? state-dir state-dirs
  state-creature-at state-creature-named state-items-at state-free? state-ring? item-class? item-class-in? item-class
  item-name creature-name creature-trait? creature-prop creature-kind state-a-kind)
(import roguelike/combat combat-player-attacks! combat-hurt-player!)
(import roguelike/creatures
  creatures-spawn! creatures-guardian! creatures-wander! creatures-act! creatures-door-diagonal? creatures-shown?)
(import roguelike/items
  items-spawn! items-place-sure! items-place-caches! items-place-goal! items-place-pages! items-goal-held? items-name items-worn
  items-pack-lines
  items-by-letter items-pickup!
  items-drop! items-quaff! items-read! items-zap! items-eat! items-fill! items-wield! items-wear! items-take-off!
  items-put-on! items-remove!)
(import roguelike/quests quests-place! quests-talk! quests-keepers!)
(import roguelike/chain chain-build!)
(import roguelike/traps traps-found-at traps-place! traps-step! traps-search!)
(import roguelike/interiors interiors-door! interiors-params interiors-prop1)
(import roguelike/data data-all data-one data-get data-region)
(import roguelike/scale scale-rung scale-seconds scale-check!)

(def %gm-roll2 (fn (_ g spec) (state-roll (game-rng g) (List ref 0 spec) (List ref 1 spec))))

; --- levels ------------------------------------------------------------------

; What is in view, from where the player stands: by the room, or by
; sight within the set's (view N); the cells beside, with the lamp out
; under the set's (lamp ...); nothing, blind.
(def %gm-light!
  (fn (_ g)
    (def p (game-player g))
    (def view (if (%gm-dark? g) 1 (game-param1 g (lit view) 0)))
    (match ((< 0 (player-condition p (lit blind))) (map-light! (game-map g) -9 -9))
           ((< 0 view) (map-light-radius! (game-map g) (player-r p) (player-c p) view))
           (#t (map-light! (game-map g) (player-r p) (player-c p))))
    (%gm-tales! g)))

; The (tale "LINE" ...) of each kind come into view for the first time
; this game, a line a message: what it is, and what has changed it.
(def %gm-tales!
  (fn (_ g)
    (List for-each
      (fn (_ cr)
        (when (creatures-shown? g cr)
          (unless (List any? (fn (_ n) (str=? n (creature-name cr))) (game-told g))
            ((fn (_ lines)
               (unless (null? lines)
                 (do (List for-each (fn (_ line) (state-say! g line)) lines)
                     (game-told! g (pair (creature-name cr) (game-told g))))))
             (creature-prop cr (lit tale) ())))))
      (game-creatures g))))

; The band's guardian's name, on the band's last level, else "".
(def %gm-guardian-name
  (fn (_ g)
    (def b (game-band g))
    (if (if (null? b) #t (not (= (game-depth g) (band-to b)))) "" (band-prop1 b (lit guardian) ""))))
; The band's guardian, alive on this level, or nil.
(def %gm-guardian
  (fn (_ g)
    (def name (%gm-guardian-name g))
    (if (str=? name "") () (state-creature-named g name))))

; Where the player lands, asked for cell AT: it, when free, else the
; nearest free cell along the same edge, else anywhere free.
(def %gm-landing
  (fn (_ g at)
    (def m (game-map g))
    (def side? (if (= (rest at) 0) #t (= (rest at) (- (map-cols m) 1))))
    (def span (if side? (map-rows m) (map-cols m)))
    (def try (fn (_ k) (if side? (pair (+ (first at) k) (rest at)) (pair (first at) (+ (rest at) k)))))
    (def found
      ((fn (self k)
         (match ((< span k) ())
                ((state-free? g (first (try k)) (rest (try k))) (try k))
                ((state-free? g (first (try (- 0 k))) (rest (try (- 0 k)))) (try (- 0 k)))
                (#t (self (+ k 1)))))
       0))
    (if (null? found) (dungeon-spot (game-rng g) m (fn (_ r c) (state-free? g r c)) 100) found)))

; A level made for the depth by PARAMS, the set's forms or an
; interior's before them: HOSTILE? on the way up, with more creatures
; and all awake; the player ARRIVING at the stairs up or down, or at a
; cell, (R . C), or as near it as is free.  The band's guardian waits
; on the way down only.  A screen made may lay a door.  The making
; leaves some 8 million objects behind, collected here.
(def %gm-level!
  (fn (_ g params hostile? arriving)
    (def m (dungeon-generate (game-rng g) (- (game-rows g) 2) (game-cols g) (game-depth g) params))
    (game-map! g m)
    (game-creatures! g ())
    (game-floor! g ())
    (game-traps! g ())
    (def at (match ((eq? arriving (lit up)) (map-up m)) ((eq? arriving (lit down)) (map-down m)) (#t (%gm-landing g arriving))))
    (player-at! (game-player g) (first at) (rest at))
    (when (if (game-screens? g) (null? (game-inside g)) #f) (interiors-door! g))
    (%gm-light! g)
    (creatures-spawn! g (+ (%gm-roll2 g (data-one params (lit creatures) (list 3 6))) (if hostile? 3 0)) hostile?)
    (unless (if hostile? #t (str=? (%gm-guardian-name g) "")) (creatures-guardian! g (%gm-guardian-name g)))
    (items-spawn! g (%gm-roll2 g (data-one params (lit items) (list 4 8))))
    (unless hostile? (items-place-sure! g))
    (items-place-caches! g)
    (items-place-goal! g)
    (items-place-pages! g)
    (quests-place! g)
    (quests-keepers! g)
    (traps-place! g)
    (%gm-light! g)
    (Heap collect)))

; The band's (enter "TEXT"), said on its first level, and the (enter
; "TEXT") of the screen made, where the set names it.
(def %gm-enter-band!
  (fn (_ g)
    (def b (game-band g))
    (def s (game-screen-form g))
    (def text (if (null? b) "" (band-prop1 b (lit enter) "")))
    (def here (if (null? s) "" (data-get (rest (rest s)) (lit enter) "")))
    (unless (if (str=? text "") #t (not (= (game-depth g) (game-band-from g)))) (state-say! g text))
    (unless (str=? here "") (state-say! g here))))

(def %gm-descend!
  (fn (_ g)
    (game-depth! g (+ (game-depth g) 1))
    (when (< (game-deepest g) (game-depth g)) (game-deepest! g (game-depth g)))
    (%gm-level! g (game-forms g) #f (lit up))
    (state-tell! g (lit stairs-down) "You descend to level {level}." (list (pair "level" (Str8 str (game-depth g)))))
    (%gm-enter-band! g)))

(def %gm-ascend!
  (fn (_ g)
    (game-depth! g (- (game-depth g) 1))
    (match
      ((game-below? g) (if (= (game-depth g) 0) (%gm-come-up! g)
                         (do (%gm-level! g (game-forms g) (items-goal-held? g) (lit down))
                             (state-tell! g (lit stairs-up) "You climb to level {level}." (list (pair "level" (Str8 str (game-depth g))))))))
      ((= (game-depth g) 0)
        (do (game-over! g (lit won))
            (state-tell! g (lit won) "You climb into daylight.  You have won." ())))
      (#t (do (%gm-level! g (game-forms g) #t (lit down))
              (state-tell! g (lit stairs-up) "You climb to level {level}." (list (pair "level" (Str8 str (game-depth g))))))))))

; --- the world of screens ----------------------------------------------------

; The level in hand kept under its key, its screen's or its
; interior's; the level kept as LEVEL taken up again.
(def %gm-keep!
  (fn (_ g)
    (game-keep! g (game-level-key g) (list (game-map g) (game-creatures g) (game-floor g) (game-traps g)))))
(def %gm-restore!
  (fn (_ g level)
    (game-map! g (List ref 0 level))
    (game-creatures! g (List ref 1 level))
    (game-floor! g (List ref 2 level))
    (game-traps! g (List ref 3 level))))

; Screen X Y entered, the player landing at or near cell AT: its level
; taken up again, or made and its band's word said.
(def %gm-enter-screen!
  (fn (_ g x y at)
    (def kept (game-kept-level g (game-screen-key g x y)))
    (game-screen! g (pair x y))
    (game-depth! g (game-screen-distance g x y))
    (when (< (game-deepest g) (game-depth g)) (game-deepest! g (game-depth g)))
    (if (null? kept)
      (do (%gm-level! g (game-forms g) #f at) (%gm-enter-band! g))
      (do (%gm-restore! g kept)
          ((fn (_ land) (player-at! (game-player g) (first land) (rest land))) (%gm-landing g at))
          (%gm-light! g)
          (%gm-note-floor! g)))
    (%gm-keep! g)))

; Through the door of the screen stood on into the interior NAME behind
; it: its level taken up again, or made by its forms and its (enter
; "TEXT") said, the player on its way out.
(def %gm-go-in!
  (fn (_ g name)
    (def subs (list (pair "name" name)))
    (%gm-keep! g)
    (game-inside! g name)
    (def kept (game-kept-level g (game-level-key g)))
    (if (null? kept)
      (do (%gm-level! g (interiors-params g name) #f (lit up))
          (state-tell! g (lit go-in) "You go into the {name}." subs)
          ((fn (_ text) (unless (str=? text "") (state-say! g text))) (interiors-prop1 g name (lit enter) "")))
      (do (%gm-restore! g kept)
          (player-at! (game-player g) (first (map-up (game-map g))) (rest (map-up (game-map g))))
          (%gm-light! g)
          (state-tell! g (lit go-in) "You go into the {name}." subs)))
    (%gm-keep! g)))

; Out of the interior by its way out, onto its screen on the door.
(def %gm-go-out!
  (fn (_ g)
    (def subs (list (pair "name" (game-inside g))))
    (%gm-keep! g)
    (game-inside! g ())
    (%gm-restore! g (game-kept-level g (game-level-key g)))
    (player-at! (game-player g) (first (map-down (game-map g))) (rest (map-down (game-map g))))
    (%gm-light! g)
    (state-tell! g (lit go-out) "You come out of the {name}." subs)
    (%gm-keep! g)))

; Through the door of the screen stood on into the region REGION behind
; the interior NAME, the region's forms in force, the screen kept to
; come back to.  A descent: down to its first level, made, the player on
; its stairs up, the interior's (enter "TEXT") said and the band's word
; after it.  A world of screens: onto its hub, the player in its middle,
; the interior's word said and then the screen's.
(def %gm-go-below!
  (fn (_ g name region)
    (def text (interiors-prop1 g name (lit enter) ""))
    (def subs (list (pair "name" name)))
    (%gm-keep! g)
    (game-go-below! g region (data-region (game-top-set g) region))
    (if (game-screens? g)
      (do (state-tell! g (lit go-into) "You go into {name}." subs)
          (unless (str=? text "") (state-say! g text))
          (%gm-enter-screen! g (first (game-hub g)) (rest (game-hub g)) (pair (int/ (- (game-rows g) 2) 2) (int/ (game-cols g) 2))))
      (do (def went (state-text g (lit go-below) "You go down the {name}." subs))
          (game-depth! g 1)
          (%gm-level! g (game-forms g) #f (lit up))
          (state-say! g went)
          (unless (str=? text "") (state-say! g text))
          (%gm-enter-band! g)))))

; Out of the region stood in onto the door it lies behind, the set the
; door is in in force again: up out of a descent's first level, or off
; the edge of a world of screens.
(def %gm-come-up!
  (fn (_ g)
    (def left (if (game-screens? g) (lit leave) (lit come-up)))
    (game-go-above! g)
    (def name (game-door g (game-level-key g)))
    (%gm-restore! g (game-kept-level g (game-level-key g)))
    (player-at! (game-player g) (first (map-down (game-map g))) (rest (map-down (game-map g))))
    (%gm-light! g)
    (state-tell! g left (if (eq? left (lit leave)) "You leave {name}." "You climb out of the {name}.") (list (pair "name" name)))
    (%gm-keep! g)))

; Whether the player stands at home (see game-home), out of doors, in
; the region home is in and none inside it.
(def %gm-at-home?
  (fn (_ g)
    (def home (game-home g))
    (def here (game-screen g))
    (match ((not (game-screens? g)) #f)
           ((not (null? (game-inside g))) #f)
           ((< 1 (List length (game-regions g))) #f)
           ((not (str=? (game-place g) (first home))) #f)
           (#t (if (= (first here) (List ref 1 home)) (= (rest here) (rest (rest home))) #f)))))

; With the game's goal in hand at home, the win: by a step there, or by
; the goal given there.
(def %gm-home!
  (fn (_ g)
    (def goal (first (data-one (game-top-set g) (lit goal) (list "the prize" "*" 20))))
    (when (match ((not (null? (game-over g))) #f)
                 ((not (List any? (fn (_ it) (if (item-class? it (lit goal)) (str=? (item-name it) goal) #f)) (game-pack g))) #f)
                 (#t (%gm-at-home? g)))
      (do (game-over! g (lit won))
          (state-tell! g (lit won) "You bring {goal} home.  You have won." (list (pair "goal" goal)))))))

; A step DR DC off the edge of the screen: onto the next screen, the
; player landing on the facing edge; at the edge of a region's world,
; out onto its door; or, at the world's edge, nowhere and no turn.
(def %gm-cross!
  (fn (_ g dr dc)
    (def p (game-player g))
    (def m (game-map g))
    (def r (+ (player-r p) dr))
    (def c (+ (player-c p) dc))
    (def dx (match ((< c 0) -1) ((< (- (map-cols m) 1) c) 1) (#t 0)))
    (def dy (match ((< r 0) -1) ((< (- (map-rows m) 1) r) 1) (#t 0)))
    (def x (+ (first (game-screen g)) dx))
    (def y (+ (rest (game-screen g)) dy))
    (def clamp (fn (_ v n) (match ((< v 0) 0) ((< (- n 1) v) (- n 1)) (#t v))))
    (def at (pair (if (= dy 0) (clamp r (map-rows m)) (if (< dy 0) (- (map-rows m) 1) 0))
                  (if (= dx 0) (clamp c (map-cols m)) (if (< dx 0) (- (map-cols m) 1) 0))))
    (match ((game-screen-in? g x y) (do (%gm-keep! g) (%gm-enter-screen! g x y at) #t))
           ((game-below? g) (do (%gm-keep! g) (%gm-come-up! g) #t))
           (#t (do (state-tell! g (lit edge) "The world ends here." ()) #f)))))

; The world as rows of screens: @ the one stood on, . one visited.
(def %gm-world-lines
  (fn (_ g)
    (def here (game-screen g))
    (List map
      (fn (_ y)
        (Str8 join " "
          (List map (fn (_ x) (match ((if (= x (first here)) (= y (rest here)) #f) "@")
                                     ((not (null? (game-kept-level g (game-screen-key g x y)))) ".")
                                     (#t " ")))
                    (List range 0 (game-world-cols g)))))
      (List range 0 (game-world-rows g)))))

; A game on SET from SEED, ROWS by COLS, its chain of quests drawn from
; the set's scenes: on level 1, or on the hub screen of a world of
; screens, in its middle, and with the set's (start NAME), through the
; door of the interior NAME there, which the hub must lay.  A set naming
; a scale off the ladder raises.
(def game-make
  (fn (_ set seed rows cols)
    (scale-check! set)
    (def g (game-new set seed rows cols))
    (def start (data-get set (lit start) ""))
    (chain-build! g)
    (if (game-screens? g)
      (%gm-enter-screen! g (first (game-hub g)) (rest (game-hub g)) (pair (int/ (- rows 2) 2) (int/ cols 2)))
      (%gm-descend! g))
    (unless (str=? start "")
      (do (unless ((fn (_ d) (if (str? d) (str=? d start) #f)) (game-door g (game-level-key g)))
            (Err raise (lit arg) "the hub laid no door to the set's start" start))
          (%gm-go-below! g start (interiors-prop1 g start (lit region) ""))))
    (state-clear-messages! g)
    (state-clear-log! g)
    (state-tell! g (lit welcome) "You enter the dungeon." ())
    (game-told! g ())
    (%gm-tales! g)
    (%gm-enter-band! g)
    (Heap collect)
    g))

; --- the turn ----------------------------------------------------------------

; Whether hunger is past nothing under the set's (starve N).
(def %gm-starving?
  (fn (_ g) (if (< 0 (game-param1 g (lit starve) 0)) (< (player-food (game-player g)) 0) #f)))

; The seconds a turn takes here: a cell walked at the level's scale,
; an interior's own or 1, out of doors the screen's, band's or set's.
(def %gm-seconds
  (fn (_ g)
    (def in (game-inside g))
    (scale-seconds (scale-rung (if (null? in) (data-get (game-forms g) (lit scale) 1) (interiors-prop1 g in (lit scale) 1))))))

; How many times every N seconds comes round from the clock at WAS to
; the clock at NOW.
(def %gm-every (fn (_ n was now) (- (int/ now n) (int/ was n))))

; Whether FROM to TO came down to MARK or past it.
(def %gm-reached? (fn (_ mark from to) (if (< mark from) (not (< mark to)) #f)))

; Food is seconds of it, the set's (hunger STORE HUNGRY WEAK MOST DEATH):
; STORE at the start, felt at HUNGRY and weakening at WEAK, MOST the
; most eaten (2000), and, past nothing with no (starve N), death at
; DEATH seconds under (150).  A ring of sustenance halves the cost.
; Under (starve N) a hit point goes every N seconds past nothing.
(def %gm-hunger!
  (fn (_ g was now)
    (def p (game-player g))
    (def spec (game-param g (lit hunger) (list 1300 300 150)))
    (def starve (game-param1 g (lit starve) 0))
    (def s (- now was))
    (def before (player-food p))
    (unless (< (List ref 0 spec) 1)
      (player-food! p (- before (if (state-ring? g (lit sustenance)) (int/ (+ s (- 1 (% (game-turn g) 2))) 2) s))))
    (def f (player-food p))
    (match
      ((< (List ref 0 spec) 1) ())
      ((%gm-reached? (List ref 1 spec) before f) (state-tell! g (lit hungry) "You are getting hungry." ()))
      ((%gm-reached? (List ref 2 spec) before f) (state-tell! g (lit weak) "You are weak with hunger." ()))
      ((%gm-starving? g)
        ((fn (_ k)
           (when (< 0 k)
             (do (state-tell! g (lit starving) "You are starving." ())
                 (combat-hurt-player! g k (state-text g (lit starved) "starved to death" ())))))
         (%gm-every starve was now)))
      ((< f (- 0 (if (< 4 (List length spec)) (List ref 4 spec) 150)))
        (combat-hurt-player! g 10000 (state-text g (lit starved) "starved to death" ())))
      ((if (< f 0) (state-chance? (game-rng g) 15) #f)
        (do (state-tell! g (lit faint) "You faint from lack of food." ()) (creatures-act! g)))
      (#t ()))))

; A hit point back every so many seconds: the set's (regen N), two
; fewer a level, four at least; every third second with a ring of
; regeneration; none while starving.
(def %gm-regen!
  (fn (_ g was now)
    (def p (game-player g))
    (def period (if (state-ring? g (lit regeneration)) 3
                  ((fn (_ n) (if (< n 4) 4 n)) (- (game-param1 g (lit regen) 20) (* 2 (- (player-level p) 1))))))
    (def k (if (%gm-starving? g) 0 (%gm-every period was now)))
    (def hp (+ (player-hp p) k))
    (when (if (< 0 k) (< (player-hp p) (player-hpmax p)) #f)
      (player-hp! p (if (< (player-hpmax p) hp) (player-hpmax p) hp)))))

; The lamp, where the set has (lamp FULL LOW): FULL seconds of oil when
; full, lit full the first turn the player is there with none lit yet,
; then burning a second a second, said when it is down to LOW and when
; it goes out.
(def %gm-lamp!
  (fn (_ g was now)
    (def spec (game-param g (lit lamp) ()))
    (def p (game-player g))
    (def before (player-lamp p))
    (def left ((fn (_ n) (if (< n 0) 0 n)) (- before (- now was))))
    (match ((null? spec) ())
           ((< before 0) (do (player-lamp! p (List ref 0 spec)) (state-tell! g (lit lamp-lit) "You light your lamp." ())))
           (#t (do (player-lamp! p left)
                   (match ((%gm-reached? 0 before left) (state-tell! g (lit lamp-out) "Your lamp goes out." ()))
                          ((%gm-reached? (List ref 1 spec) before left) (state-tell! g (lit lamp-low) "Your lamp burns low." ()))
                          (#t ())))))))

; Whether the lamp is out under the set's (lamp ...).
(def %gm-dark?
  (fn (_ g) (if (null? (game-param g (lit lamp) ())) #f (= 0 (player-lamp (game-player g))))))

(def %gm-creatures-act!
  (fn (_ g)
    (def p (game-player g))
    (match ((not (null? (game-over g))) ())
           ((< 0 (player-condition p (lit hasted))) (when (= 0 (% (game-turn g) 2)) (creatures-act! g)))
           ((< 0 (player-condition p (lit slowed))) (do (creatures-act! g) (creatures-act! g)))
           (#t (creatures-act! g)))))

(def %gm-end-turn!
  (fn (_ g)
    (def was (game-clock g))
    (def now (+ was (%gm-seconds g)))
    (game-turn! g (+ (game-turn g) 1))
    (game-clock! g now)
    (%gm-hunger! g was now)
    (%gm-regen! g was now)
    (%gm-lamp! g was now)
    (%gm-creatures-act! g)
    (player-tick! (game-player g))
    (creatures-wander! g)
    (%gm-light! g)
    (%gm-home! g)))

; --- moving ------------------------------------------------------------------

(def %gm-note-floor!
  (fn (_ g)
    (def here (state-items-at g (player-r (game-player g)) (player-c (game-player g))))
    (unless (null? here) (items-pickup! g))))
; A door stood on, out of doors in a world of screens, says where it goes;
; a building's door says the building, by its (enter "TEXT") or its name.
(def %gm-note-door!
  (fn (_ g)
    (def p (game-player g))
    (def name (if (if (game-screens? g) (null? (game-inside g)) #f) (game-door g (game-level-key g)) ()))
    (when (if (null? name) #f (= (map-tile (game-map g) (player-r p) (player-c p)) tile-down))
      (state-tell! g (lit door) "There is a way into the {name} here." (list (pair "name" name))))
    (def place (if (= (map-tile (game-map g) (player-r p) (player-c p)) tile-door) (map-place-at (game-map g) (player-r p) (player-c p)) ()))
    (unless (null? place)
      ((fn (_ b)
         (def enter (if (null? b) "" (data-get (rest b) (lit enter) "")))
         (if (str=? enter "")
           (state-tell! g (lit building) "The door of {name}." (list (pair "name" (first place))))
           (state-say! g enter)))
       (List find (fn (_ f) (str=? (first f) (first place))) (data-all (game-forms g) (lit building)))))))

; A step DR DC, a blow at what stands there, or a word with it when it
; talks: whether a turn passed.  Confused, the step goes any way; held,
; nowhere.  A wall takes no turn.
(def %gm-move!
  (fn (_ g dr dc)
    (def p (game-player g))
    (def d (if (< 0 (player-condition p (lit confused))) ((game-rng g) choice (state-dirs)) (pair dr dc)))
    (def r (+ (player-r p) (first d)))
    (def c (+ (player-c p) (rest d)))
    (def cr (state-creature-at g r c))
    (match
      ((< 0 (player-condition p (lit held))) (do (state-tell! g (lit held-still) "You are held fast and cannot move." ()) #t))
      ((not (null? cr)) (if (creature-trait? cr (lit talks)) (quests-talk! g cr) (do (combat-player-attacks! g cr) #t)))
      ((not (map-in? (game-map g) r c))
        (if (if (game-screens? g) (null? (game-inside g)) #f) (%gm-cross! g (first d) (rest d)) #f))
      ((not (map-walkable? (game-map g) r c)) #f)
      ((creatures-door-diagonal? (game-map g) (player-r p) (player-c p) (first d) (rest d)) #f)
      (#t (do (player-at! p r c) (%gm-light! g) (traps-step! g) (%gm-note-floor! g) (%gm-note-door! g) #t)))))

; --- exploring ---------------------------------------------------------------

; Whether R C of M, seen and walkable, lies beside a cell not yet seen
; that is not rock: a place worth walking to.
(def game-frontier?
  (fn (_ m r c)
    (List any? (fn (_ d)
                 (def rr (+ r (first d)))
                 (def cc (+ c (rest d)))
                 (match ((not (map-in? m rr cc)) #f) ((map-seen? m rr cc) #f) (#t (not (= (map-tile m rr cc) tile-rock)))))
      (state-dirs))))

; Whether one of the people stands at R C: walking into them talks, so
; a walk goes round them.
(def %gm-person-at?
  (fn (_ g r c)
    (def cr (state-creature-at g r c))
    (if (null? cr) #f (creature-trait? cr (lit talks)))))

; The first step, (DR . DC), of the shortest walk over seen cells, a
; found trap or one of the people never among them, from the player to the nearest frontier,
; or nil with none: a breadth-first search, each cell remembering the
; first step that reached it.
(def %gm-explore-step
  (fn (_ g)
    (def m (game-map g))
    (def p (game-player g))
    (def cols (map-cols m))
    (def came (Vector make (* (map-rows m) cols) ()))
    (def at (fn (_ r c) (+ (* r cols) c)))
    (def reach
      (fn (_ r c step)
        (List reject null?
          (List map (fn (_ d)
                      (def rr (+ r (first d)))
                      (def cc (+ c (rest d)))
                      (match ((not (map-in? m rr cc)) ())
                             ((not (map-seen? m rr cc)) ())
                             ((not (map-walkable? m rr cc)) ())
                             ((not (null? (traps-found-at g rr cc))) ())
                             ((%gm-person-at? g rr cc) ())
                             ((creatures-door-diagonal? m r c (first d) (rest d)) ())
                             ((not (null? (Vector ref (at rr cc) came))) ())
                             (#t (do (Vector set! (at rr cc) (if (null? step) d step) came) (pair rr cc)))))
                    (state-dirs)))))
    (def search
      (fn (self front back)
        (match
          ((null? front) (if (null? back) () (self (List reverse back) ())))
          (#t (do (def r (first (first front)))
                  (def c (rest (first front)))
                  (def step (Vector ref (at r c) came))
                  (if (if (eq? step #t) #f (game-frontier? m r c)) step
                    (self (rest front) (List append (reach r c (if (eq? step #t) () step)) back))))))))
    (Vector set! (at (player-r p) (player-c p)) #t came)
    (search (list (pair (player-r p) (player-c p))) ())))

; One step toward what is not yet seen, a turn: whether the walk goes
; on.  It ends with a creature in view that does not talk, a question
; asked, nothing left to see, a hundred steps taken, or the game over.
(def game-explore!
  (fn (_ g)
    (def n (game-exploring g))
    (def stop (fn (_) (game-exploring! g ()) #f))
    (def shown (if (null? n) () (List find (fn (_ cr) (if (creature-trait? cr (lit talks)) #f (creatures-shown? g cr))) (game-creatures g))))
    (match
      ((null? n) #f)
      ((not (null? (game-over g))) (stop))
      ((not (null? (game-ask g))) (stop))
      ((not (null? shown))
        (do (when (= n 0) (state-tell! g (lit creature-near) "You see {a-name}." (list (pair "name" (creature-name shown)) (pair "a-name" (state-a-kind (creature-kind shown)))))) (stop)))
      ((= n 100) (stop))
      (#t ((fn (_ d)
             (if (null? d) (do (when (= n 0) (state-tell! g (lit explored) "Nothing left to explore." ())) (stop))
               (do (%gm-move! g (first d) (rest d)) (%gm-end-turn! g) (Heap collect) (game-exploring! g (+ n 1)) #t)))
           (%gm-explore-step g))))))

; --- commands ----------------------------------------------------------------

(def %gm-stairs-down!
  (fn (_ g)
    (def p (game-player g))
    (def guardian (%gm-guardian g))
    (match
      ((not (null? (game-inside g)))
        (do (state-tell! g (lit no-way-on) "There is no way further in." ()) #f))
      ((not (= (map-tile (game-map g) (player-r p) (player-c p)) tile-down))
        (do (state-tell! g (lit no-stairs) "There are no stairs here." ()) #f))
      ((game-screens? g)
        ((fn (_ name)
           (match ((null? name) (do (state-tell! g (lit no-stairs) "There are no stairs here." ()) #f))
                  ((str=? (interiors-prop1 g name (lit region) "") "") (do (%gm-go-in! g name) #t))
                  (#t (do (%gm-go-below! g name (interiors-prop1 g name (lit region) "")) #t))))
         (game-door g (game-level-key g))))
      ((not (null? guardian))
        (do (state-tell! g (lit barred) "The {name} bars the way down." (list (pair "name" (creature-name guardian)))) #f))
      (#t (do (%gm-descend! g) #t)))))
(def %gm-stairs-up!
  (fn (_ g)
    (def p (game-player g))
    (match
      ((not (= (map-tile (game-map g) (player-r p) (player-c p)) tile-up))
        (do (state-tell! g (lit no-stairs) "There are no stairs here." ()) #f))
      ((not (null? (game-inside g)))
        (do (%gm-go-out! g) #t))
      ((game-below? g) (do (%gm-ascend! g) #t))
      ((not (items-goal-held? g))
        (do (state-tell! g (lit no-way-up) "The way up is sealed." ()) #f))
      (#t (do (%gm-ascend! g) #t)))))

; A question: (KIND PROMPT HANDLER . CLASS).  item: a letter, HANDLER
; given the pack item, of CLASS, one or a list, when named; dir:
; HANDLER given (DR . DC); yn: HANDLER on y; look: one of %gm-on-keys,
; LINES shown till then; choose: HANDLER given the key, LINES shown till
; then.
(def %gm-ask-item!
  (fn (_ g prompt class handler)
    (if (null? (List filter (fn (_ it) (item-class-in? it class)) (game-pack g)))
      (do (state-tell! g (lit none-such) "You have nothing like that." ()) #f)
      (do (game-ask! g (list (lit item) prompt handler class)) #f))))
(def %gm-ask-dir! (fn (_ g prompt handler) (game-ask! g (list (lit dir) prompt handler)) #f))
(def %gm-look! (fn (_ g prompt lines) (game-ask! g (list (lit look) prompt () lines)) #f))

(def %gm-pack-lines
  (fn (_ g)
    (if (null? (game-pack g)) (list "Your pack is empty.") (items-pack-lines g ()))))

(def %gm-zap!
  (fn (_ g it)
    (%gm-ask-dir! g "Which way?" (fn (_ d) (items-zap! g it (first d) (rest d)) #t))
    #f))

(def %gm-use-ring!
  (fn (_ g it)
    (if (not (str=? (items-worn g it) "")) (do (items-remove! g it) #t) (do (items-put-on! g it) #t))))

; (KEY . (fn (_ g) ...)): whether a turn passed.
(def %gm-commands
  (list
    (pair "." (fn (_ g) #t))
    (pair "s" (fn (_ g) (do (traps-search! g) #t)))
    (pair ">" (fn (_ g) (%gm-stairs-down! g)))
    (pair "<" (fn (_ g) (%gm-stairs-up! g)))
    (pair "," (fn (_ g) (items-pickup! g)))
    (pair "g" (fn (_ g) (items-pickup! g)))
    (pair "i" (fn (_ g) (%gm-look! g "Your pack:" (%gm-pack-lines g))))
    (pair "q" (fn (_ g) (%gm-ask-item! g "Quaff what?" (lit potion) (fn (_ it) (items-quaff! g it) #t))))
    (pair "r" (fn (_ g) (%gm-ask-item! g "Read what?" (list (lit scroll) (lit page)) (fn (_ it) (items-read! g it) #t))))
    (pair "z" (fn (_ g) (%gm-ask-item! g "Zap what?" (lit wand) (fn (_ it) (%gm-zap! g it)))))
    (pair "e" (fn (_ g) (%gm-ask-item! g "Eat what?" (lit food) (fn (_ it) (items-eat! g it) #t))))
    (pair "f" (fn (_ g) (%gm-ask-item! g "Fill the lamp with what?" (lit oil) (fn (_ it) (items-fill! g it)))))
    (pair "w" (fn (_ g) (%gm-ask-item! g "Wield what?" (lit weapon) (fn (_ it) (items-wield! g it) #t))))
    (pair "W" (fn (_ g) (%gm-ask-item! g "Wear what?" (lit armour) (fn (_ it) (items-wear! g it) #t))))
    (pair "T" (fn (_ g) (do (items-take-off! g) #t)))
    (pair "P" (fn (_ g) (%gm-ask-item! g "Put on what?" (lit ring) (fn (_ it) (%gm-use-ring! g it)))))
    (pair "R" (fn (_ g) (%gm-ask-item! g "Remove what?" (lit ring) (fn (_ it) (%gm-use-ring! g it)))))
    (pair "d" (fn (_ g) (%gm-ask-item! g "Drop what?" () (fn (_ it) (items-drop! g it) #t))))
    (pair "o" (fn (_ g) (do (game-exploring! g 0) (game-explore! g) #f)))
    (pair "L" (fn (_ g) (%gm-look! g "Lately:" (List reverse (List take 20 (game-log g))))))
    (pair "m" (fn (_ g) (if (game-screens? g) (%gm-look! g (state-text g (lit world-map) "The world:" ()) (%gm-world-lines g))
                          (do (state-tell! g (lit no-world-map) "You know only the level you stand on." ()) #f))))
    (pair "?" (fn (_ g) (%gm-look! g "The keys:" (game-help g))))
    (pair "Q" (fn (_ g) (do (game-ask! g (list (lit yn) "Really quit?" (fn (_) (game-over! g (lit quit)) (game-epitaph! g "quit") #f))) #f)))
    (pair "S" (fn (_ g) (do (game-over! g (lit saved)) #f)))))

(def %gm-key=? (fn (_ a b) (if (str? a) (if (str? b) (str=? a b) #f) (eq? a b))))

; --- --More-- ----------------------------------------------------------------

; Whether MSGS, joined, leave room for --More-- on the row.
(def %gm-fits? (fn (_ g msgs) (< (Str8 length (Str8 join "  " msgs)) (- (game-cols g) 9))))
; MSGS cut where they stop fitting: (SHOWN . REST), the first always shown.
(def %gm-split
  (fn (self g msgs taken)
    (match ((null? msgs) (pair (List reverse taken) ()))
           ((null? taken) (self g (rest msgs) (list (first msgs))))
           ((%gm-fits? g (List reverse (pair (first msgs) taken))) (self g (rest msgs) (pair (first msgs) taken)))
           (#t (pair (List reverse taken) msgs)))))
; The turn's messages that outrun the row held back, asked for by --More--.
(def game-more!
  (fn (_ g)
    (def msgs (game-messages g))
    (unless (if (%gm-fits? g msgs) #t (not (null? (game-ask g))))
      ((fn (_ split)
         (game-messages! g (List reverse (first split)))
         (game-ask! g (list (lit more) "" () (rest split))))
       (%gm-split g msgs ())))))

; The key answers the question being asked: whether a turn passed.
(def %gm-answer!
  (fn (_ g key)
    (def q (game-ask g))
    (game-ask! g ())
    (match
      ((eq? (first q) (lit more)) (do (game-messages! g (List reverse (List ref 3 q))) (game-more! g) #f))
      ((eq? key (lit escape)) #f)
      ((eq? (first q) (lit look)) #f)
      ((eq? (first q) (lit yn)) (if (%gm-key=? key "y") ((List ref 2 q)) #f))
      ((eq? (first q) (lit choose)) ((List ref 2 q) key))
      ((eq? (first q) (lit dir)) ((fn (_ d) (if (null? d) #f ((List ref 2 q) d))) (state-dir key)))
      (#t (%gm-answer-item! g q key)))))
(def %gm-answer-item!
  (fn (_ g q key)
    (def it (if (str? key) (items-by-letter g key) ()))
    (match
      ((null? it) (do (state-tell! g (lit no-such-item) "You have no such thing." ()) #f))
      ((not (item-class-in? it (List ref 3 q)))
        (do (state-tell! g (lit wrong-kind) "You can't do that with {name}." (list (pair "name" (items-name g it)))) #f))
      (#t ((List ref 2 q) it)))))

(def %gm-command!
  (fn (_ g key)
    (def d (state-dir key))
    (def cmd (if (null? d) (List find (fn (_ p) (%gm-key=? (first p) key)) %gm-commands) ()))
    (match
      ((not (null? d)) (%gm-move! g (first d) (rest d)))
      ((not (null? cmd)) ((rest cmd) g))
      ((eq? key (lit clear)) #f)
      (#t (do (state-tell! g (lit unknown-key) "Unknown key.  ? lists them." ()) #f)))))

; KEY taken, as (Term key) decodes keys: a move or a command, or the
; answer to what was asked.  A key ends a walk.  After a game is over,
; keys do nothing.  What drives the game collects the heap at its own
; pace, a turn making some 1.6 million objects; the game collects after
; making a level, some 8 million (see %gm-level!).
(def game-key!
  (fn (_ g key)
    (unless (%gm-held? g key)
      (do (state-clear-messages! g)
          (game-exploring! g ())
          (match
            ((not (null? (game-over g))) ())
            ((not (null? (game-ask g))) (when (%gm-answer! g key) (%gm-end-turn! g)))
            (#t (when (%gm-command! g key) (%gm-end-turn! g))))
          (game-more! g)))))

; The keys that go on past --More-- and put away what is being looked
; at: enter and space, and nothing else (a gamepad's A is sent as enter).
; Any other key is taken as a slip and changes nothing, so a message is
; not lost to a key meant for the turn after it.
(def %gm-on-keys (list (lit enter) " "))
; Whether game G is showing a --More-- or a thing looked at, waiting
; for one of %gm-on-keys.
(def game-waiting?
  (fn (_ g)
    (def q (game-ask g))
    (if (null? q) #f (if (eq? (first q) (lit more)) #t (eq? (first q) (lit look))))))
(def %gm-held?
  (fn (_ g key) (if (game-waiting? g) (not (List any? (fn (_ k) (%gm-key=? k key)) %gm-on-keys)) #f)))

; --- the score -----------------------------------------------------------------

; A set's (score (NAME POINTS) ...), the set the game began on, below
; or not, is what a game is worth: POINTS for each of NAME, among gold,
; deepest (the level, or the screens out from the hub), won, quests (done), screens (visited) and places (gone
; into); and (par TURNS POINTS), POINTS a turn under TURNS on a win.
; What it does not name counts nothing.  A set without one scores
; gold, fifty a level and a thousand for the win.
(def %gm-score-default (list (list (lit gold) 1) (list (lit deepest) 50) (list (lit won) 1000)))

; The count of what game G did by NAME.
(def %gm-count
  (fn (_ g name)
    (def keys (List map first (game-kept g)))
    (def place? (fn (_ k) (Str8 ends? ">" k)))
    (match ((eq? name (lit gold)) (player-gold (game-player g)))
           ((eq? name (lit deepest)) (game-deepest g))
           ((eq? name (lit won)) (if (eq? (game-over g) (lit won)) 1 0))
           ((eq? name (lit quests)) (List count-if (fn (_ p) (eq? (rest p) (lit done))) (game-quests g)))
           ((eq? name (lit screens)) (List count-if (fn (_ k) (not (place? k))) keys))
           ((eq? name (lit places)) (List count-if place? keys))
           (#t 0))))

; Each line of the score that counts, in the set's order: (NAME COUNT
; POINTS).  The par's count is the turns under it.
(def game-score-lines
  (fn (_ g)
    (def line
      (fn (_ w)
        (def name (first w))
        (def under (- (List ref 1 w) (game-turn g)))
        (def count
          (if (eq? name (lit par))
            (if (if (eq? (game-over g) (lit won)) (< 0 under) #f) under 0)
            (%gm-count g name)))
        (list name count (* count (List ref (if (eq? name (lit par)) 2 1) w)))))
    (List filter (fn (_ l) (not (= 0 (List ref 2 l)))) (List map line (data-one (game-top-set g) (lit score) %gm-score-default)))))

; What game G is worth.
(def game-score (fn (_ g) (List fold (fn (_ a l) (+ a (List ref 2 l))) 0 (game-score-lines g))))

; Each line's message: (NAME KEY DEFAULT).
(def %gm-score-words
  (list (list (lit gold) (lit score-gold) "{points} for {count} gold")
        (list (lit deepest) (lit score-deepest) "{points} for reaching depth {count}")
        (list (lit won) (lit score-won) "{points} for the win")
        (list (lit quests) (lit score-quests) "{points} for quests done: {count}")
        (list (lit screens) (lit score-screens) "{points} for screens visited: {count}")
        (list (lit places) (lit score-places) "{points} for places gone into: {count}")
        (list (lit par) (lit score-par) "{points} for turns under par: {count}")))

; The score's lines in words, the set's (message score-NAME "TEXT")
; with {points} and {count}.
(def game-score-text
  (fn (_ g)
    (List map
      (fn (_ l)
        (def w (List find (fn (_ w) (eq? (first w) (first l))) %gm-score-words))
        (state-text g (List ref 1 w) (List ref 2 w)
          (list (pair "points" (Str8 str (List ref 2 l))) (pair "count" (Str8 str (List ref 1 l))))))
      (game-score-lines g))))

; The keys, for the help screen.
(def game-help
  (fn (_ g)
    (list "h j k l y u b n  move; the arrows too.  Walk into a creature to attack it, or to talk."
          ".      rest a turn          s      search beside you"
          ",  g   pick up what is here"
          "o      explore what is unseen until something comes into view; a key stops"
          "L      what has been said lately   m      the map of the world"
          ">      down, or in a door   <      up with the goal, or out of a door"
          "i      your pack            d      drop a thing"
          "q      quaff a potion       r      read a scroll or a page"
          "z      zap a wand           e      eat"
          "w      wield a weapon       W  T   wear armour, take it off"
          "P  R   put on a ring, take it off"
          "f      fill the lamp from a flask"
          "S      save and leave       Q      quit"
          "?      these keys           Esc    stop asking")))

(provide roguelike/game game-make game-key! game-waiting? game-explore! game-frontier? game-more! game-score game-score-lines game-score-text game-help)
