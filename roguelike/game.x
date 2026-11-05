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
; again.  The stairs down make a new level; the stairs up are sealed
; until the goal is held, and then each level climbed is made anew,
; roused and hostile.  Nothing here touches a terminal: a spec gives
; keys and reads the state.

(module roguelike/game)

(import x/type/vector)
(import roguelike/map map-tile map-up map-down map-walkable? map-light! tile-down tile-up)
(import roguelike/dungeon dungeon-generate)
(import roguelike/state
  game-rng game-set game-depth game-depth! game-map game-map! game-player game-creatures game-creatures!
  game-floor game-floor! game-pack game-turn game-turn! game-ask game-ask! game-over game-over!
  game-deepest game-deepest! game-rows game-cols game-param game-param1 game-new game-epitaph!
  game-messages game-messages!
  player-r player-c player-at! player-hp player-hp! player-hpmax player-level player-food player-food!
  player-condition player-tick! player-armour player-rings player-gold
  state-say! state-tell! state-text state-clear-messages! state-roll state-chance? state-dir state-dirs
  state-creature-at state-items-at state-ring? item-class? item-class item-name)
(import roguelike/combat combat-player-attacks! combat-hurt-player!)
(import roguelike/creatures creatures-spawn! creatures-wander! creatures-act! creatures-door-diagonal?)
(import roguelike/items
  items-spawn! items-place-goal! items-goal-held? items-name items-worn items-by-letter items-pickup!
  items-drop! items-quaff! items-read! items-zap! items-eat! items-wield! items-wear! items-take-off!
  items-put-on! items-remove!)

(def %gm-roll2 (fn (_ g spec) (state-roll (game-rng g) (List ref 0 spec) (List ref 1 spec))))

; --- levels ------------------------------------------------------------------

; What is in view, from where the player stands; nothing, blind.
(def %gm-light!
  (fn (_ g)
    (def p (game-player g))
    (if (< 0 (player-condition p (lit blind))) (map-light! (game-map g) -9 -9)
      (map-light! (game-map g) (player-r p) (player-c p)))))

; A level made for the depth: HOSTILE? on the way up, with more
; creatures and all awake; the player ARRIVING at the stairs up or down.
(def %gm-level!
  (fn (_ g hostile? arriving)
    (def m (dungeon-generate (game-rng g) (- (game-rows g) 2) (game-cols g) (game-depth g) (game-set g)))
    (game-map! g m)
    (game-creatures! g ())
    (game-floor! g ())
    (def at (if (eq? arriving (lit up)) (map-up m) (map-down m)))
    (player-at! (game-player g) (first at) (rest at))
    (%gm-light! g)
    (creatures-spawn! g (+ (%gm-roll2 g (game-param g (lit creatures) (list 3 6))) (if hostile? 3 0)) hostile?)
    (items-spawn! g (%gm-roll2 g (game-param g (lit items) (list 4 8))))
    (items-place-goal! g)
    (%gm-light! g)))

(def %gm-descend!
  (fn (_ g)
    (game-depth! g (+ (game-depth g) 1))
    (when (< (game-deepest g) (game-depth g)) (game-deepest! g (game-depth g)))
    (%gm-level! g #f (lit up))
    (state-tell! g (lit stairs-down) "You descend to level {level}." (list (pair "level" (Str8 str (game-depth g)))))))

(def %gm-ascend!
  (fn (_ g)
    (game-depth! g (- (game-depth g) 1))
    (if (= (game-depth g) 0)
      (do (game-over! g (lit won))
          (state-tell! g (lit won) "You climb into daylight.  You have won." ()))
      (do (%gm-level! g #t (lit down))
          (state-tell! g (lit stairs-up) "You climb to level {level}." (list (pair "level" (Str8 str (game-depth g)))))))))

; A game on SET from SEED, ROWS by COLS, on level 1.
(def game-make
  (fn (_ set seed rows cols)
    (def g (game-new set seed rows cols))
    (%gm-descend! g)
    (state-clear-messages! g)
    (state-tell! g (lit welcome) "You enter the dungeon." ())
    g))

; --- the turn ----------------------------------------------------------------

(def %gm-hunger!
  (fn (_ g)
    (def p (game-player g))
    (def spec (game-param g (lit hunger) (list 1300 300 150)))
    (unless (if (state-ring? g (lit sustenance)) (= 1 (% (game-turn g) 2)) #f)
      (player-food! p (- (player-food p) 1)))
    (def f (player-food p))
    (match
      ((= f (List ref 1 spec)) (state-tell! g (lit hungry) "You are getting hungry." ()))
      ((= f (List ref 2 spec)) (state-tell! g (lit weak) "You are weak with hunger." ()))
      ((< f -150) (combat-hurt-player! g 10000 (state-text g (lit starved) "starved to death" ())))
      ((if (< f 0) (state-chance? (game-rng g) 15) #f)
        (do (state-tell! g (lit faint) "You faint from lack of food." ()) (creatures-act! g)))
      (#t ()))))

; A hit point back every so many turns: the set's (regen N), two fewer
; a level, four at least; every third turn with a ring of regeneration.
(def %gm-regen!
  (fn (_ g)
    (def p (game-player g))
    (def period (if (state-ring? g (lit regeneration)) 3
                  ((fn (_ n) (if (< n 4) 4 n)) (- (game-param1 g (lit regen) 20) (* 2 (- (player-level p) 1))))))
    (when (if (= 0 (% (game-turn g) period)) (< (player-hp p) (player-hpmax p)) #f)
      (player-hp! p (+ (player-hp p) 1)))))

(def %gm-creatures-act!
  (fn (_ g)
    (def p (game-player g))
    (match ((not (null? (game-over g))) ())
           ((< 0 (player-condition p (lit hasted))) (when (= 0 (% (game-turn g) 2)) (creatures-act! g)))
           ((< 0 (player-condition p (lit slowed))) (do (creatures-act! g) (creatures-act! g)))
           (#t (creatures-act! g)))))

(def %gm-end-turn!
  (fn (_ g)
    (game-turn! g (+ (game-turn g) 1))
    (%gm-hunger! g)
    (%gm-regen! g)
    (%gm-creatures-act! g)
    (player-tick! (game-player g))
    (creatures-wander! g)
    (%gm-light! g)))

; --- moving ------------------------------------------------------------------

(def %gm-note-floor!
  (fn (_ g)
    (def here (state-items-at g (player-r (game-player g)) (player-c (game-player g))))
    (unless (null? here) (items-pickup! g))))

; A step DR DC, or a blow at what stands there: whether a turn passed.
; Confused, the step goes any way; held, nowhere.  A wall takes no turn.
(def %gm-move!
  (fn (_ g dr dc)
    (def p (game-player g))
    (def d (if (< 0 (player-condition p (lit confused))) ((game-rng g) choice (state-dirs)) (pair dr dc)))
    (def r (+ (player-r p) (first d)))
    (def c (+ (player-c p) (rest d)))
    (def cr (state-creature-at g r c))
    (match
      ((< 0 (player-condition p (lit held))) (do (state-tell! g (lit held-still) "You are held fast and cannot move." ()) #t))
      ((not (null? cr)) (do (combat-player-attacks! g cr) #t))
      ((not (map-walkable? (game-map g) r c)) #f)
      ((creatures-door-diagonal? (game-map g) (player-r p) (player-c p) (first d) (rest d)) #f)
      (#t (do (player-at! p r c) (%gm-light! g) (%gm-note-floor! g) #t)))))

; --- commands ----------------------------------------------------------------

(def %gm-stairs-down!
  (fn (_ g)
    (def p (game-player g))
    (if (= (map-tile (game-map g) (player-r p) (player-c p)) tile-down) (do (%gm-descend! g) #t)
      (do (state-tell! g (lit no-stairs) "There are no stairs here." ()) #f))))
(def %gm-stairs-up!
  (fn (_ g)
    (def p (game-player g))
    (match
      ((not (= (map-tile (game-map g) (player-r p) (player-c p)) tile-up))
        (do (state-tell! g (lit no-stairs) "There are no stairs here." ()) #f))
      ((not (items-goal-held? g))
        (do (state-tell! g (lit no-way-up) "The way up is sealed." ()) #f))
      (#t (do (%gm-ascend! g) #t)))))

; A question: (KIND PROMPT HANDLER . CLASS).  item: a letter, HANDLER
; given the pack item, of CLASS when one is named; dir: HANDLER given
; (DR . DC); yn: HANDLER on y; look: any key, LINES shown till then.
(def %gm-ask-item!
  (fn (_ g prompt class handler)
    (if (null? (List filter (fn (_ it) (if (null? class) #t (item-class? it class))) (game-pack g)))
      (do (state-tell! g (lit none-such) "You have nothing like that." ()) #f)
      (do (game-ask! g (list (lit item) prompt handler class)) #f))))
(def %gm-ask-dir! (fn (_ g prompt handler) (game-ask! g (list (lit dir) prompt handler)) #f))
(def %gm-look! (fn (_ g prompt lines) (game-ask! g (list (lit look) prompt () lines)) #f))

(def %gm-pack-lines
  (fn (_ g)
    (if (null? (game-pack g)) (list "Your pack is empty.")
      (List map (fn (_ it) (Str8 append (item-letter it) ") " (items-name g it) (items-worn g it))) (game-pack g)))))

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
    (pair "s" (fn (_ g) #t))
    (pair ">" (fn (_ g) (%gm-stairs-down! g)))
    (pair "<" (fn (_ g) (%gm-stairs-up! g)))
    (pair "," (fn (_ g) (items-pickup! g)))
    (pair "g" (fn (_ g) (items-pickup! g)))
    (pair "i" (fn (_ g) (%gm-look! g "Your pack:" (%gm-pack-lines g))))
    (pair "q" (fn (_ g) (%gm-ask-item! g "Quaff what?" (lit potion) (fn (_ it) (items-quaff! g it) #t))))
    (pair "r" (fn (_ g) (%gm-ask-item! g "Read what?" (lit scroll) (fn (_ it) (items-read! g it) #t))))
    (pair "z" (fn (_ g) (%gm-ask-item! g "Zap what?" (lit wand) (fn (_ it) (%gm-zap! g it)))))
    (pair "e" (fn (_ g) (%gm-ask-item! g "Eat what?" (lit food) (fn (_ it) (items-eat! g it) #t))))
    (pair "w" (fn (_ g) (%gm-ask-item! g "Wield what?" (lit weapon) (fn (_ it) (items-wield! g it) #t))))
    (pair "W" (fn (_ g) (%gm-ask-item! g "Wear what?" (lit armour) (fn (_ it) (items-wear! g it) #t))))
    (pair "T" (fn (_ g) (do (items-take-off! g) #t)))
    (pair "P" (fn (_ g) (%gm-ask-item! g "Put on what?" (lit ring) (fn (_ it) (%gm-use-ring! g it)))))
    (pair "R" (fn (_ g) (%gm-ask-item! g "Remove what?" (lit ring) (fn (_ it) (%gm-use-ring! g it)))))
    (pair "d" (fn (_ g) (%gm-ask-item! g "Drop what?" () (fn (_ it) (items-drop! g it) #t))))
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
      ((eq? (first q) (lit dir)) ((fn (_ d) (if (null? d) #f ((List ref 2 q) d))) (state-dir key)))
      (#t (%gm-answer-item! g q key)))))
(def %gm-answer-item!
  (fn (_ g q key)
    (def it (if (str? key) (items-by-letter g key) ()))
    (match
      ((null? it) (do (state-tell! g (lit no-such-item) "You have no such thing." ()) #f))
      ((if (null? (List ref 3 q)) #f (not (item-class? it (List ref 3 q))))
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
; answer to what was asked.  After a game is over, keys do nothing.
(def game-key!
  (fn (_ g key)
    (state-clear-messages! g)
    (match
      ((not (null? (game-over g))) ())
      ((not (null? (game-ask g))) (when (%gm-answer! g key) (%gm-end-turn! g)))
      (#t (when (%gm-command! g key) (%gm-end-turn! g))))
    (game-more! g)))

; Gold, fifty a level reached, a thousand for the win.
(def game-score
  (fn (_ g)
    (+ (player-gold (game-player g)) (+ (* 50 (game-deepest g)) (if (eq? (game-over g) (lit won)) 1000 0)))))

; The keys, for the help screen.
(def game-help
  (fn (_ g)
    (list "h j k l y u b n  move; the arrows too.  Walk into a creature to attack it."
          ".  s   rest a turn          ,  g   pick up what is here"
          ">      go down the stairs   <      go up, with the goal in hand"
          "i      your pack            d      drop a thing"
          "q      quaff a potion       r      read a scroll"
          "z      zap a wand           e      eat"
          "w      wield a weapon       W  T   wear armour, take it off"
          "P  R   put on a ring, take it off"
          "S      save and leave       Q      quit"
          "?      these keys           Esc    stop asking")))

(provide roguelike/game game-make game-key! game-more! game-score game-help)
