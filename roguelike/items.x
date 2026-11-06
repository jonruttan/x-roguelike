; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/items.x -- things found, carried, named and used
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A level's items are drawn from the set's (item CLASS NAME . PROPS)
; forms by their (rarity N), with gold by the set's (gold CHANCE LO HI),
; the goal on its level, and each (page NAME DEPTH LINE ...) on its,
; once: a page is read like a scroll, shows its lines, and is kept.
; A potion, scroll, wand or ring is known by
; a guise until one of its kind is used; the guises are shuffled each
; game.  Using a thing takes its (effect NAME ARGS...): each effect is
; a function in a table here, so a set may use any of them in any
; item.  A ring's (bonus KEY N) is read by the state, not here.

(module roguelike/items)

(import x/type/vector)
(import roguelike/data data-all data-glyph)
(import roguelike/map
  map-walkable? map-reveal! map-rooms map-rooms! map-room-at room-r0 room-c0 room-r1 room-c1 map-tile tile-floor)
(import roguelike/dungeon dungeon-spot)
(import roguelike/state
  game-rng game-set game-depth game-map game-player game-floor game-floor! game-pack game-pack! game-ask!
  game-guises game-known game-known! game-param game-param1 game-goal-placed? game-goal-placed!
  game-pages-placed game-page-placed!
  player-r player-c player-at! player-hp player-hp! player-hpmax player-hpmax! player-str player-str!
  player-strmax player-strmax! player-armour player-armour! player-weapon player-weapon! player-rings
  player-rings! player-food player-food! player-condition! player-gold player-gold!
  creature-hp creature-hp! creature-at! creature-condition! creature-name
  item-make item-form item-class item-name item-prop item-prop1 item-count item-count! item-charges
  item-charges! item-enchant item-enchant! item-letter item-letter! item-r item-c item-at! item-class? item-class-in?
  state-say! state-tell! state-roll state-chance? state-creature-at state-items-at state-free?
  state-remove-floor! state-remove-pack! state-ring?)
(import roguelike/combat combat-kill! combat-hurt-player!)
(import roguelike/creatures creatures-wake-all! creatures-scare!)

; --- spawning ----------------------------------------------------------------

(def %it-forms (fn (_ g) (data-all (game-set g) (lit item))))
(def %it-weight (fn (_ form) (def r (Assoc find (lit rarity) (rest (rest form)))) (if (null? r) 1 (List ref 1 r))))
(def %it-pick
  (fn (self forms n)
    (if (< n (%it-weight (first forms))) (first forms) (self (rest forms) (- n (%it-weight (first forms)))))))
; A random item form, by rarity.
(def %it-random-form
  (fn (_ g)
    (def forms (%it-forms g))
    (%it-pick forms ((game-rng g) int (List fold (fn (_ acc f) (+ acc (%it-weight f))) 0 forms)))))

; A new item of FORM: a wand's charges rolled from its (charges LO HI).
(def items-new
  (fn (_ g form)
    (def ch (Assoc find (lit charges) (rest (rest form))))
    (item-make form 1 (if (null? ch) 0 (state-roll (game-rng g) (List ref 1 ch) (List ref 2 ch))))))

(def %it-gold-form (list (lit gold) "gold"))
(def %it-gold
  (fn (_ g)
    (def spec (game-param g (lit gold) (list 35 5 25)))
    (item-make %it-gold-form (* (game-depth g) (state-roll (game-rng g) (List ref 1 spec) (List ref 2 spec))) 0)))

(def %it-free? (fn (_ g) (fn (_ r c) (null? (state-items-at g r c)))))
(def %it-put!
  (fn (_ g it)
    (def at (dungeon-spot (game-rng g) (game-map g) (%it-free? g) 100))
    (unless (null? at)
      (do (item-at! it (first at) (rest at)) (game-floor! g (pair it (game-floor g)))))))

; N things on the level: gold by the set's chance, else an item.
(def items-spawn!
  (fn (self g n)
    (unless (< n 1)
      (do (%it-put! g (if (state-chance? (game-rng g) (first (game-param g (lit gold) (list 35 5 25)))) (%it-gold g)
                        (items-new g (%it-random-form g))))
          (self g (- n 1))))))

; The goal, (goal NAME GLYPH DEPTH), on its level, once.
(def items-place-goal!
  (fn (_ g)
    (def goal (game-param g (lit goal) (list "the prize" "*" 20)))
    (when (if (game-goal-placed? g) #f (= (game-depth g) (List ref 2 goal)))
      (do (%it-put! g (item-make (list (lit goal) (first goal)) 1 0))
          (game-goal-placed! g)))))

(def items-goal-held? (fn (_ g) (List any? (fn (_ it) (item-class? it (lit goal))) (game-pack g))))

; A page's item form from its (page NAME DEPTH LINE ...): (page NAME
; (text LINE ...)).
(def items-page-form (fn (_ args) (list (lit page) (first args) (pair (lit text) (rest (rest args))))))
; The set's page named NAME, as an item form, or nil.
(def items-page-named
  (fn (_ g name)
    (def hit (List find (fn (_ a) (str=? (first a) name)) (data-all (game-set g) (lit page))))
    (if (null? hit) () (items-page-form hit))))

; Each page of the depth not yet placed, on the level.
(def items-place-pages!
  (fn (_ g)
    (List for-each
      (fn (_ args)
        (when (if (= (game-depth g) (List ref 1 args)) (not (List includes? (first args) (game-pages-placed g))) #f)
          (do (%it-put! g (item-make (items-page-form args) 1 0))
              (game-page-placed! g (first args)))))
      (data-all (game-set g) (lit page)))))

; --- naming ------------------------------------------------------------------

(def %it-str=? (fn (_ a) (fn (_ b) (str=? a b))))
; Known: used before, or of a class the set's (known CLASS ...) names.
(def items-known?
  (fn (_ g it)
    (if (List includes? (item-class it) (game-param g (lit known) ())) #t
      (List any? (%it-str=? (item-name it)) (game-known g)))))
(def items-know!
  (fn (_ g it) (unless (items-known? g it) (game-known! g (pair (item-name it) (game-known g))))))

; The guise of IT: the Nth name of its class's guises, N its place among
; the set's items of that class.
(def %it-index
  (fn (self name forms n)
    (match ((null? forms) 0)
           ((str=? (List ref 1 (first forms)) name) n)
           (#t (self name (rest forms) (+ n 1))))))
(def %it-guise
  (fn (_ g it)
    (def names (Assoc get (item-class it) (game-guises g)))
    (def same (List filter (fn (_ f) (eq? (first f) (item-class it))) (%it-forms g)))
    (if (null? names) "strange" (List ref (% (%it-index (item-name it) same 0) (List length names)) names))))

(def %it-vowel? (fn (_ s) (List any? (fn (_ v) (Str8 starts? v s)) (list "a" "e" "i" "o" "u"))))
(def %it-an (fn (_ s) (Str8 append (if (%it-vowel? s) "an " "a ") s)))
(def %it-signed (fn (_ n) (if (< n 0) (Str8 str n) (Str8 append "+" (Str8 str n)))))
(def %it-plural (fn (_ it s) (if (< 1 (item-count it)) (Str8 append (Str8 str (item-count it)) " " s "s") (%it-an s))))

; Each class's name: known or guised for the magical ones.
(def %it-name-magic
  (fn (_ g it kind unknown)
    (if (items-known? g it) (Str8 append (%it-an kind) " of " (item-name it))
      (%it-an (Str8 append (%it-guise g it) unknown)))))
(def %it-namers
  (list
    (pair (lit potion) (fn (_ g it) (%it-name-magic g it "potion" " potion")))
    (pair (lit scroll) (fn (_ g it) (if (items-known? g it) (Str8 append "a scroll of " (item-name it))
                                      (Str8 append "a scroll titled '" (%it-guise g it) "'"))))
    (pair (lit wand) (fn (_ g it) (Str8 append (%it-name-magic g it "wand" " wand")
                                    (if (items-known? g it) (Str8 append " (" (Str8 str (item-charges it)) ")") ""))))
    (pair (lit ring) (fn (_ g it) (%it-name-magic g it "ring" " ring")))
    (pair (lit weapon) (fn (_ g it) (Str8 append (%it-an (item-name it))
                                      (if (= (item-enchant it) 0) "" (Str8 append " " (%it-signed (item-enchant it)))))))
    (pair (lit armour) (fn (_ g it) (Str8 append (item-name it) " ["
                                      (Str8 str (+ (item-prop1 it (lit armour) 0) (item-enchant it))) "]")))
    (pair (lit food) (fn (_ g it) (%it-plural it (item-name it))))
    (pair (lit gold) (fn (_ g it) (Str8 append (Str8 str (item-count it)) " gold pieces")))
    (pair (lit goal) (fn (_ g it) (item-name it)))
    (pair (lit page) (fn (_ g it) (item-name it)))))
(def items-name
  (fn (_ g it)
    (def namer (Assoc get (item-class it) %it-namers))
    (if (null? namer) (item-name it) (namer g it))))

; What IT is worn as, after its name in the pack.
(def items-worn
  (fn (_ g it)
    (def p (game-player g))
    (match ((same? it (player-weapon p)) " (in hand)")
           ((same? it (player-armour p)) " (worn)")
           ((List any? (fn (_ r) (same? r it)) (player-rings p)) " (on hand)")
           (#t ""))))

(def items-glyph (fn (_ g it) (data-glyph (game-set g) (item-class it) "?")))

; The pack's items of CLASS, one or a list, or all of them for nil, a
; line each: "a) a short blade (in hand)".
(def items-pack-lines
  (fn (_ g class)
    (List map (fn (_ it) (Str8 append (item-letter it) ") " (items-name g it) (items-worn g it)))
      (List filter (fn (_ it) (item-class-in? it class)) (game-pack g)))))

; --- the pack ----------------------------------------------------------------

(def %it-letters "abcdefghijklmnopqrstuvwxyz")
(def %it-letter-used? (fn (_ g l) (List any? (fn (_ it) (str=? (item-letter it) l)) (game-pack g))))
; The first letter no pack item has, or nil with all twenty-six taken.
(def %it-free-letter
  (fn (self g i)
    (match ((= i 26) ())
           ((%it-letter-used? g (Str8 sub i 1 %it-letters)) (self g (+ i 1)))
           (#t (Str8 sub i 1 %it-letters)))))
(def items-by-letter (fn (_ g l) (List find (fn (_ it) (str=? (item-letter it) l)) (game-pack g))))

; A pack item like IT, for a food that stacks, or nil.
(def %it-stack
  (fn (_ g it)
    (if (item-class? it (lit food))
      (List find (fn (_ x) (if (item-class? x (lit food)) (str=? (item-name x) (item-name it)) #f)) (game-pack g))
      ())))

; What is under the player picked up: gold to the purse, the rest to
; the pack.  Answers whether anything was.
(def items-pickup!
  (fn (_ g)
    (def p (game-player g))
    (def here (state-items-at g (player-r p) (player-c p)))
    (if (null? here) (do (state-tell! g (lit nothing-here) "There is nothing here to pick up." ()) #f)
      (do (List for-each (fn (_ it) (%it-take! g it)) here) #t))))
(def %it-take!
  (fn (_ g it)
    (def p (game-player g))
    (def stack (%it-stack g it))
    (def letter (%it-free-letter g 0))
    (match
      ((item-class? it (lit gold))
        (do (state-remove-floor! g it)
            (player-gold! p (+ (player-gold p) (item-count it)))
            (state-tell! g (lit gold) "You find {n} gold pieces." (list (pair "n" (Str8 str (item-count it)))))))
      ((not (null? stack))
        (do (state-remove-floor! g it)
            (item-count! stack (+ (item-count stack) (item-count it)))
            (state-tell! g (lit picked-up) "{letter}) {name}" (list (pair "letter" (item-letter stack)) (pair "name" (items-name g stack))))))
      ((null? letter) (state-tell! g (lit pack-full) "Your pack is full." ()))
      (#t (do (state-remove-floor! g it)
              (item-letter! it letter)
              (game-pack! g (List append (game-pack g) (list it)))
              (when (item-class? it (lit goal))
                (state-tell! g (lit found-goal) "You have {name}!  Now climb back to the light." (list (pair "name" (item-name it)))))
              (state-tell! g (lit picked-up) "{letter}) {name}" (list (pair "letter" letter) (pair "name" (items-name g it)))))))))

; IT, or one of a stack, put down where the player stands.
(def items-drop!
  (fn (_ g it)
    (def p (game-player g))
    (match
      ((not (str=? (items-worn g it) "")) (state-tell! g (lit in-use) "You would have to take that off first." ()))
      (#t (do (def dropped (if (< 1 (item-count it)) (item-make (item-form it) 1 0) it))
              (if (same? dropped it) (do (state-remove-pack! g it) (item-letter! it ()))
                (item-count! it (- (item-count it) 1)))
              (item-at! dropped (player-r p) (player-c p))
              (game-floor! g (pair dropped (game-floor g)))
              (state-tell! g (lit dropped) "You drop {name}." (list (pair "name" (items-name g dropped)))))))))

; One of IT used up: a stack shrinks, a single thing leaves the pack.
(def %it-consume!
  (fn (_ g it)
    (if (< 1 (item-count it)) (item-count! it (- (item-count it) 1))
      (do (state-remove-pack! g it) (item-letter! it ())))))

; --- effects -----------------------------------------------------------------

(def %it-heal!
  (fn (_ g lo hi)
    (def p (game-player g))
    (def n (+ (player-hp p) (state-roll (game-rng g) lo hi)))
    (if (< (player-hpmax p) n)
      (do (player-hpmax! p (+ (player-hpmax p) 1)) (player-hp! p (player-hpmax p)))
      (player-hp! p n))
    (state-tell! g (lit healed) "You feel better." ())))
(def %it-strength!
  (fn (_ g n)
    (def p (game-player g))
    (player-str! p (+ (player-str p) n))
    (when (< (player-strmax p) (player-str p)) (player-strmax! p (player-str p)))
    (state-tell! g (lit stronger) "You feel stronger." ())))
(def %it-poison!
  (fn (_ g lo hi)
    (def p (game-player g))
    (if (state-ring? g (lit sustenance)) (state-tell! g (lit unaffected) "You feel momentarily sick." ())
      (do (def n (- (player-str p) (state-roll (game-rng g) lo hi)))
          (player-str! p (if (< n 3) 3 n))
          (state-tell! g (lit poisoned) "You feel very sick." ())))))
(def %it-condition!
  (fn (_ g name turns key default)
    (player-condition! (game-player g) name turns)
    (state-tell! g key default ())))
(def %it-teleport!
  (fn (_ g)
    (def at (dungeon-spot (game-rng g) (game-map g) (fn (_ r c) (state-free? g r c)) 100))
    (unless (null? at) (player-at! (game-player g) (first at) (rest at)))
    (state-tell! g (lit teleported) "You are somewhere else." ())))
(def %it-enchant!
  (fn (_ g it key default none)
    (if (null? it) (state-tell! g (lit nothing-happens) none ())
      (do (item-enchant! it (+ (item-enchant it) 1)) (state-tell! g key default ())))))
(def %it-light!
  (fn (_ g)
    (def m (game-map g))
    (def room (map-room-at m (player-r (game-player g)) (player-c (game-player g))))
    (if (null? room) (state-tell! g (lit nothing-happens) "The passage flickers." ())
      (do (map-rooms! m (List map (fn (_ r) (if (same? r room) (list (room-r0 r) (room-c0 r) (room-r1 r) (room-c1 r) #t) r)) (map-rooms m)))
          (state-tell! g (lit lit) "The room fills with light." ())))))
(def %it-hold!
  (fn (_ g turns)
    (def p (game-player g))
    (List for-each
      (fn (_ d)
        (def cr (state-creature-at g (+ (player-r p) (first d)) (+ (player-c p) (rest d))))
        (unless (null? cr) (creature-condition! cr (lit held) turns)))
      (list (pair -1 -1) (pair -1 0) (pair -1 1) (pair 0 -1) (pair 0 1) (pair 1 -1) (pair 1 0) (pair 1 1)))
    (state-tell! g (lit held-others) "Everything near you stands still." ())))
(def %it-identify!
  (fn (_ g)
    (game-ask! g (list (lit item) "Name what?"
                       (fn (_ it)
                         (items-know! g it)
                         (state-tell! g (lit named) "{name}" (list (pair "name" (items-name g it))))
                         #f)
                       ()))))

; (EFFECT . (fn (_ g args) ...)) for potions and scrolls.
(def %it-effects
  (list
    (pair (lit heal) (fn (_ g a) (%it-heal! g (List ref 0 a) (List ref 1 a))))
    (pair (lit strength) (fn (_ g a) (%it-strength! g (List ref 0 a))))
    (pair (lit restore) (fn (_ g a) (do (player-str! (game-player g) (player-strmax (game-player g))) (state-tell! g (lit restored) "You feel yourself again." ()))))
    (pair (lit poison) (fn (_ g a) (%it-poison! g (List ref 0 a) (List ref 1 a))))
    (pair (lit haste) (fn (_ g a) (%it-condition! g (lit hasted) (List ref 0 a) (lit hasted) "You feel yourself speed up.")))
    (pair (lit confusion) (fn (_ g a) (%it-condition! g (lit confused) (List ref 0 a) (lit confused) "Wait, what's going on?")))
    (pair (lit blindness) (fn (_ g a) (%it-condition! g (lit blind) (List ref 0 a) (lit blinded) "A veil falls over your eyes.")))
    (pair (lit seeing) (fn (_ g a) (%it-condition! g (lit seeing) (List ref 0 a) (lit seeing) "You sense everything that moves.")))
    (pair (lit mapping) (fn (_ g a) (do (map-reveal! (game-map g)) (state-tell! g (lit mapped) "The level's shape comes to you." ()))))
    (pair (lit teleport) (fn (_ g a) (%it-teleport! g)))
    (pair (lit identify) (fn (_ g a) (%it-identify! g)))
    (pair (lit enchant-weapon) (fn (_ g a) (%it-enchant! g (player-weapon (game-player g)) (lit keener) "Your weapon glows for a moment." "Your hands tingle.")))
    (pair (lit enchant-armour) (fn (_ g a) (%it-enchant! g (player-armour (game-player g)) (lit harder) "Your armour glows for a moment." "Your skin tingles.")))
    (pair (lit fear) (fn (_ g a) (do (creatures-scare! g) (state-tell! g (lit feared) "You hear a terrible wail." ()))))
    (pair (lit aggravate) (fn (_ g a) (do (creatures-wake-all! g) (state-tell! g (lit clamour) "A great clamour fills the dungeon." ()))))
    (pair (lit light) (fn (_ g a) (%it-light! g)))
    (pair (lit hold) (fn (_ g a) (%it-hold! g (List ref 0 a))))))

(def %it-effect!
  (fn (_ g it)
    (def e (item-prop it (lit effect) ()))
    (def f (if (null? e) () (Assoc get (first e) %it-effects)))
    (if (null? f) (state-tell! g (lit nothing-happens) "Nothing happens." ()) (f g (rest e)))))

; A potion drunk, a scroll read: its effect, and its kind known.
(def items-quaff!
  (fn (_ g it)
    (items-know! g it)
    (%it-consume! g it)
    (%it-effect! g it)))
; A scroll read; a page shown, its lines over the level, and kept.
(def items-read!
  (fn (_ g it)
    (if (item-class? it (lit page))
      (game-ask! g (list (lit look) (item-name it) () (item-prop it (lit text) ())))
      (items-quaff! g it))))

; The first creature from the player along DR DC within RANGE, or nil.
(def items-target
  (fn (self g r c dr dc range)
    (match ((= range 0) ())
           ((not (map-walkable? (game-map g) (+ r dr) (+ c dc))) ())
           (#t ((fn (_ cr) (if (null? cr) (self g (+ r dr) (+ c dc) dr dc (- range 1)) cr))
                (state-creature-at g (+ r dr) (+ c dc)))))))

(def %it-bolt!
  (fn (_ g cr lo hi)
    (def n (state-roll (game-rng g) lo hi))
    (creature-hp! cr (- (creature-hp cr) n))
    (state-tell! g (lit bolt) "The bolt strikes the {name}." (list (pair "name" (creature-name cr))))
    (when (< (creature-hp cr) 1) (combat-kill! g cr))
    n))
(def %it-zaps
  (list
    (pair (lit bolt) (fn (_ g cr a) (%it-bolt! g cr (List ref 0 a) (List ref 1 a))))
    (pair (lit slow) (fn (_ g cr a) (do (creature-condition! cr (lit slowed) (List ref 0 a))
                                        (state-tell! g (lit slowed-other) "The {name} slows." (list (pair "name" (creature-name cr)))))))
    (pair (lit teleport-other)
      (fn (_ g cr a)
        (def at (dungeon-spot (game-rng g) (game-map g) (fn (_ r c) (state-free? g r c)) 100))
        (unless (null? at) (creature-at! cr (first at) (rest at)))
        (state-tell! g (lit banished) "The {name} vanishes." (list (pair "name" (creature-name cr))))))
    (pair (lit drain)
      (fn (_ g cr a)
        (def p (game-player g))
        (def n (%it-bolt! g cr (List ref 0 a) (List ref 1 a)))
        (player-hp! p (if (< (player-hpmax p) (+ (player-hp p) n)) (player-hpmax p) (+ (player-hp p) n)))))))

; A wand zapped along DR DC.
(def items-zap!
  (fn (_ g it dr dc)
    (def p (game-player g))
    (def e (item-prop it (lit effect) ()))
    (def f (if (null? e) () (Assoc get (first e) %it-zaps)))
    (def cr (items-target g (player-r p) (player-c p) dr dc 8))
    (match
      ((< (item-charges it) 1) (state-tell! g (lit no-charges) "The wand sputters." ()))
      (#t (do (item-charges! it (- (item-charges it) 1))
              (items-know! g it)
              (if (if (null? f) #t (null? cr)) (state-tell! g (lit nothing-happens) "Nothing happens." ())
                (f g cr (rest e))))))))

(def items-eat!
  (fn (_ g it)
    (def p (game-player g))
    (def n (+ (player-food p) (item-prop1 it (lit nutrition) 500)))
    (player-food! p (if (< 2000 n) 2000 n))
    (%it-consume! g it)
    (state-tell! g (lit ate) "That tasted {how}." (list (pair "how" (if ((game-rng g) bool) "good" "awful"))))))

(def items-wield!
  (fn (_ g it)
    (def p (game-player g))
    (player-weapon! p it)
    (state-tell! g (lit wielding) "You are now wielding {name}." (list (pair "name" (items-name g it))))))
(def items-wear!
  (fn (_ g it)
    (def p (game-player g))
    (if (not (null? (player-armour p))) (state-tell! g (lit already-wearing) "You are already wearing armour." ())
      (do (player-armour! p it)
          (state-tell! g (lit wearing) "You are now wearing {name}." (list (pair "name" (items-name g it))))))))
(def items-take-off!
  (fn (_ g)
    (def p (game-player g))
    (if (null? (player-armour p)) (state-tell! g (lit not-wearing) "You are not wearing any armour." ())
      (do (state-tell! g (lit took-off) "You take off {name}." (list (pair "name" (items-name g (player-armour p)))))
          (player-armour! p ())))))
(def items-put-on!
  (fn (_ g it)
    (def p (game-player g))
    (if (< 1 (List length (player-rings p))) (state-tell! g (lit hands-full) "You have no free hand for it." ())
      (do (player-rings! p (pair it (player-rings p)))
          (items-know! g it)
          (state-tell! g (lit put-on) "You put on {name}." (list (pair "name" (items-name g it))))))))
(def items-remove!
  (fn (_ g it)
    (def p (game-player g))
    (player-rings! p (List reject (fn (_ r) (same? r it)) (player-rings p)))
    (state-tell! g (lit removed) "You take off {name}." (list (pair "name" (items-name g it))))))

(provide roguelike/items
  items-new items-spawn! items-place-goal! items-goal-held? items-page-named items-place-pages!
  items-known? items-know! items-name items-worn
  items-glyph items-pack-lines items-by-letter items-pickup! items-drop! items-quaff! items-read! items-target items-zap!
  items-eat! items-wield! items-wear! items-take-off! items-put-on! items-remove!)
