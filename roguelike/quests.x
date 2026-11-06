; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/quests.x -- the people met below, and what they ask
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A set's (quest NAME GIVER . PROPS) puts the creature named GIVER, one
; with the talks trait, on its (level N), and what it wants: (wants
; bring ITEM ...) lays each token on a level, the last on the giver's
; and the rest on those above, or in the keeping of a (carrier "kind")
; creature there; (wants explore) asks for every cell of the giver's
; level seen.  Walking into the giver opens the quest and says its (ask
; LINE ...); with it open, its (again LINE ...), or, once the want is
; met, its (done LINE ...) and the choice of one of its (rewards (CLASS
; NAME) (CLASS NAME)).  Each thing is placed once a game.

(module roguelike/quests)

(import x/type/vector)
(import roguelike/data data-all data-prop data-prop1)
(import roguelike/map map-rows map-cols map-tile map-seen? map-each! tile-rock)
(import roguelike/dungeon dungeon-spot)
(import roguelike/state
  game-rng game-set game-depth game-map game-player game-creatures game-creatures! game-floor game-floor!
  game-pack game-ask! game-quest-state game-quest-state! game-placed? game-placed!
  player-r player-c creature-make creature-name creature-carried!
  item-make item-name item-class? item-at! item-letter!
  state-tell! state-roll state-free? state-items-at state-remove-pack!)
(import roguelike/items items-new items-pickup! items-name)

(def %qs-quests (fn (_ g) (data-all (game-set g) (lit quest))))
(def %qs-name (fn (_ q) (first q)))
(def %qs-giver (fn (_ q) (List ref 1 q)))
(def %qs-level (fn (_ q) (data-prop1 q (lit level) 0)))
(def %qs-wants (fn (_ q) (data-prop q (lit wants) ())))
(def %qs-items (fn (_ q) (def w (%qs-wants q)) (if (if (null? w) #f (eq? (first w) (lit bring))) (rest w) ())))

; The set's creature kind, or item form of CLASS, named NAME, or nil.
(def %qs-kind (fn (_ g name) (List find (fn (_ k) (str=? (first k) name)) (data-all (game-set g) (lit creature)))))
(def %qs-item-form
  (fn (_ g class name)
    (List find (fn (_ f) (if (eq? (first f) class) (str=? (List ref 1 f) name) #f)) (data-all (game-set g) (lit item)))))
; A token's form: the set's, or a bare one.
(def %qs-token (fn (_ g name) (def f (%qs-item-form g (lit token) name)) (if (null? f) (list (lit token) name) f)))

; --- placing -----------------------------------------------------------------

(def %qs-spot (fn (_ g) (dungeon-spot (game-rng g) (game-map g) (fn (_ r c) (if (state-free? g r c) (null? (state-items-at g r c)) #f)) 100)))

; A creature of KIND at R C, awake.
(def %qs-creature!
  (fn (_ g kind r c)
    (def hp (data-prop kind (lit hp) (list 1 1)))
    (def cr (creature-make kind r c (state-roll (game-rng g) (first hp) (List ref 1 hp)) (lit awake)))
    (game-creatures! g (pair cr (game-creatures g)))
    cr))

(def %qs-place-giver!
  (fn (_ g q)
    (def kind (%qs-kind g (%qs-giver q)))
    (def at (%qs-spot g))
    (unless (if (null? kind) #t (null? at))
      (do (%qs-creature! g kind (first at) (rest at))
          (game-placed! g (Str8 append "giver " (%qs-name q)))))))

; The token NAME on the level: in a carrier's keeping, else on the floor.
(def %qs-place-token!
  (fn (_ g q name)
    (def it (item-make (%qs-token g name) 1 0))
    (def carrier (%qs-kind g (data-prop1 q (lit carrier) "")))
    (def at (%qs-spot g))
    (unless (null? at)
      (do (if (null? carrier)
            (do (item-at! it (first at) (rest at)) (game-floor! g (pair it (game-floor g))))
            (creature-carried! (%qs-creature! g carrier (first at) (rest at)) it))
          (game-placed! g name)))))

; Of Q's N tokens, the Kth lies on level LEVEL - N + 1 + K.
(def %qs-place-tokens!
  (fn (_ g q)
    (def names (%qs-items q))
    (def k (- (game-depth g) (+ 1 (- (%qs-level q) (List length names)))))
    (when (if (< k 0) #f (< k (List length names)))
      ((fn (_ name) (unless (game-placed? g name) (%qs-place-token! g q name))) (List ref k names)))))

; Each quest's giver on its level, and its tokens on theirs, once.
(def quests-place!
  (fn (_ g)
    (List for-each
      (fn (_ q)
        (when (if (= (game-depth g) (%qs-level q)) (not (game-placed? g (Str8 append "giver " (%qs-name q)))) #f)
          (%qs-place-giver! g q))
        (%qs-place-tokens! g q))
      (%qs-quests g))))

; --- what is wanted ----------------------------------------------------------

(def %qs-has? (fn (_ g name) (List any? (fn (_ it) (if (item-class? it (lit token)) (str=? (item-name it) name) #f)) (game-pack g))))

; Whether every cell of the level that is not rock has been seen.
(def %qs-seen-whole?
  (fn (_ g)
    (def m (game-map g))
    (def left (Vector of 0))
    (map-each! 0 0 (- (map-rows m) 1) (- (map-cols m) 1)
      (fn (_ r c) (when (if (= (map-tile m r c) tile-rock) #f (not (map-seen? m r c))) (Vector set! 0 1 left))))
    (= 0 (Vector ref 0 left))))

(def %qs-satisfied?
  (fn (_ g q)
    (def w (%qs-wants q))
    (match ((null? w) #f)
           ((eq? (first w) (lit bring)) (List all? (fn (_ n) (%qs-has? g n)) (rest w)))
           ((eq? (first w) (lit explore)) (%qs-seen-whole? g))
           (#t #f))))

; The tokens Q wanted taken from the pack.
(def %qs-take!
  (fn (_ g q)
    (List for-each
      (fn (_ it) (when (if (item-class? it (lit token)) (List includes? (item-name it) (%qs-items q)) #f)
                   (do (state-remove-pack! g it) (item-letter! it ()))))
      (game-pack g))))

; --- talking -----------------------------------------------------------------

(def %qs-look! (fn (_ g cr lines) (game-ask! g (list (lit look) (creature-name cr) () lines))))

; The reward forms of Q, (CLASS NAME) each, as item forms.
(def %qs-rewards (fn (_ g q) (List reject null? (List map (fn (_ r) (%qs-item-form g (first r) (List ref 1 r))) (data-prop q (lit rewards) ())))))

; The reward FORM given: under the player, and picked up.
(def %qs-give!
  (fn (_ g form)
    (def it (items-new g form))
    (item-at! it (player-r (game-player g)) (player-c (game-player g)))
    (game-floor! g (pair it (game-floor g)))
    (items-pickup! g)))

; The choice of Q's rewards, after its done lines: a or b takes one.
(def %qs-offer!
  (fn (_ g q cr)
    (def forms (%qs-rewards g q))
    (def names (List map (fn (_ f) (items-name g (items-new g f))) forms))
    (def letters (list "a" "b"))
    (def choices (Str8 join "   " (List map (fn (_ i) (Str8 append (List ref i letters) ") " (List ref i names))) (List range 0 (List length names)))))
    (def pick
      (fn (_ key)
        (def i (match ((not (str? key)) ()) ((str=? key "a") 0) ((str=? key "b") 1) (#t ())))
        (if (if (null? i) #t (not (< i (List length forms)))) #f
          (do (%qs-give! g (List ref i forms)) (game-quest-state! g (%qs-name q) (lit done)) #t))))
    (if (null? forms) (do (game-quest-state! g (%qs-name q) (lit done)) (%qs-look! g cr (data-prop q (lit done) ())))
      (game-ask! g (list (lit choose) "Which will you take?" pick (List append (data-prop q (lit done) ()) (list "" choices)))))))

; The giver CR walked into: its quest opened, pressed, met, or over.  A
; turn passes.
(def quests-talk!
  (fn (_ g cr)
    (def q (List find (fn (_ q) (str=? (%qs-giver q) (creature-name cr))) (%qs-quests g)))
    (def state (if (null? q) (lit done) (game-quest-state g (%qs-name q))))
    (def subs (list (pair "name" (creature-name cr))))
    (match
      ((null? q) (state-tell! g (lit no-words) "The {name} has nothing to say." subs))
      ((eq? state (lit done)) (state-tell! g (lit quest-over) "The {name} has nothing more to ask." subs))
      ((null? state) (do (game-quest-state! g (%qs-name q) (lit open)) (%qs-look! g cr (data-prop q (lit ask) ()))))
      ((eq? state (lit reward)) (%qs-offer! g q cr))
      ((%qs-satisfied? g q) (do (%qs-take! g q) (game-quest-state! g (%qs-name q) (lit reward)) (%qs-offer! g q cr)))
      (#t (%qs-look! g cr (data-prop q (lit again) ()))))
    #t))

(provide roguelike/quests quests-place! quests-talk!)
