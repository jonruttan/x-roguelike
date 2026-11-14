; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/sound.x -- the game heard in a window
;
; The window's sound: a soundtrack and an ambient bed played by trackers
; (x/audio/tracker), a heartbeat, and the sounds of a turn, all made
; from the set's data (the sound and song forms, docs/sound.md) by
; x/audio/mixer and played on SDL's audio streams.
;
; Music and ambience are rendered a little ahead of the speaker on one
; stream, topped up each time the window's loop comes round
; (sound-pump!).  A turn's sounds are rendered once each, kept, and put
; on a stream of their own as the turn is shown (sound-turn!), so they
; are heard with the frame that shows them and never wait behind the
; music.  What a turn sounded like is read from the game before and after
; it: a step, a blow (game-blows), and every change in the player's state
; the set gives a cue: hurt, healed, weak, stronger, hungry, poisoned,
; up or down the stairs, into a new band, the lamp lit, low or out, a
; thing bought or sold.  A building has its own song and air inside.  A
; creature the turn woke cries out, seen or not, quieter the further off.
;
; Tension, 0 to 100, is what the player has to fear: a creature awake
; and near, and the wounds already taken.  It quickens the music and
; brings in its tension layer, and past a threshold a heartbeat is
; heard, faster and louder as it rises.  A blow struck either way brings
; in the place's fight music until the fighting stops, and a band's
; guardian, awake and near, its own.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module roguelike/sound)

(import x/audio/mixer)
(import x/audio/tracker)
(import x/core/doors int* int+ int- int/ int% int< int= int& obj-make obj-ref obj-set! str->sym
  str-make str->ptr ptr->int int->ptr mem-copy)
(import roguelike/data data-all data-one data-get)
(import roguelike/state game-set game-player game-depth game-map game-creatures game-pack game-over game-blows game-said game-turn
  game-band band-name game-place game-top-set game-param player-r player-c player-hp player-hpmax player-level player-gold
  player-food player-lamp player-conditions creature-r creature-c creature-state creature-name state-dist
  band-to band-prop1 state-creature-named game-inside item-count item-prop player-rings)
(import roguelike/map map-tile map-terrain map-roof-at map-place-at)
(import roguelike/creatures creatures-shown?)

(def %sd-rate 44100)
(def %sd-block 1024)
; How far the music is kept ahead of the speaker, in bytes of frames.
(def %sd-ahead (int* 4 (int/ (int* %sd-rate 3) 10)))
(def %sd-effect-streams 4)
; The heap is collected after this many blocks rendered while no key
; comes (sound-collect?): a block's garbage is small, a minute's is not.
(def %sd-collect-blocks 172)

; --- the record ----------------------------------------------------------------
;
; A vector: 0 the forms sounds are found in (%sd-forms), 1 the mixer,
; 2 the music's stream, 3 the turn's streams, 4 the music's tracker, 5
; the bed's, 6 the sounds rendered, ((KEY . (REGION . BYTES)) ...), 7
; the tension, 8 the game as it was (%sd-glance), 9 the random state,
; 10 blocks since a collect, 11 the places the music is for
; (sound-places), 12 the
; place's random sounds, 13 how loud the turn's sounds are, a
; percentage (sound-volume!), 14 the creatures as they stood
; (%sd-states), 15 the class the sound is played through, Sdl or Web
; (%sd-front), 16 the name of the song last asked for (%sd-music!), 17
; the turns left of a fight, 18 the guardian fought, or nil, 19 the
; game's turn last heard (%sd-turned?), 20 the set stood in when 0 was
; made, 21 the game's keys told last heard (game-said), 22 the sounds
; heard while a condition or a bonus holds, (SOUND EVERY GAIN) each
; (%sd-held!), 23 the mix as last set, (PITCH PACE CUT EFFECTS SWAY)
; (%sd-mix!), 24 the heartbeat's own mixer and 25 its stream, 26 how
; thin the turn's sounds are (%sd-thin), 27 the set's music effects,
; kept last, and 28 the blocks the pace has been swung (%sd-sway!).

(def %sd-vector-type ((prim-ref (lit type) (lit of)) (Vector make 0 ())))
(def %sd-get (fn (_ s k) (obj-ref s (int+ k 1))))
(def %sd-put! (fn (_ s k x) (obj-set! s (int+ k 1) x)))
(def %sd-front (fn (_ s) (%sd-get s 15)))

; --- the set's data ------------------------------------------------------------

; The forms G's sounds are found in: the set stood in, then the set the
; game began on and each of its regions, so a place's own sounds and
; songs come first and every other is the world's.
(def %sd-forms
  (fn (_ g)
    (def top (game-top-set g))
    (List append (game-set g) top (List flat-map rest (data-all top (lit region))))))

; The forms kept on S made again from G once the set stood in changes.
(def %sd-world!
  (fn (_ s g)
    (unless (same? (game-set g) (%sd-get s 20))
      (do (%sd-put! s 20 (game-set g))
          (%sd-put! s 0 (%sd-forms g))))))

(def %sd-named
  (fn (_ set head name)
    (List find (fn (_ f) (if (pair? f) (if (str? (first f)) (str=? (first f) name) #f) #f)) (data-all set head))))

; A sound's form, (sound NAME PROP ...): its voices and echoes, varied.
(def %sd-sound (fn (_ set name) (%sd-named set (lit sound) name)))
(def %sd-props (fn (_ f key) (List filter (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) (rest f))))
(def %sd-prop1 (fn (_ f key default) ((fn (_ l) (if (null? l) default (first (rest (first l))))) (%sd-props f key))))

; The voices of sound F, each with CENTS added to its detune and PAN to
; its place, at the sound's gain.
(def %sd-voices
  (fn (_ f cents pan)
    (def gain (%sd-prop1 f (lit gain) 100))
    (List map
      (fn (_ v)
        (def props (rest v))
        (def own (fn (_ key) ((fn (_ l) (if (null? l) 0 (first (rest (first l))))) (%sd-props v key))))
        (List append
          (list (list (lit detune) (int+ (own (lit detune)) cents))
                (list (lit pan) ((fn (_ p) (if (int< 100 p) 100 (if (int< p -100) -100 p))) (int+ (own (lit pan)) pan)))
                (list (lit gain) (int/ (int* gain ((fn (_ g) (if (int= g 0) 100 g)) (own (lit gain)))) 100)))
          props))
      (%sd-props f (lit voice)))))

(def %sd-song
  (fn (_ set name)
    (def f (%sd-named set (lit song) name))
    (if (null? f) () (pair (lit song) f))))

; What the first of PLACES that has one plays, from (music PLACE SONG)
; and (ambience PLACE (bed SONG) (random SOUND EVERY-MS GAIN) ...), a
; PLACE a building's name, a band's, a region's, or default for the rest.
(def %sd-for
  (fn (_ set head places)
    ((fn (self ps)
       (if (null? ps) (%sd-named set head "default")
         ((fn (_ hit) (if (null? hit) (self (rest ps)) hit)) (%sd-named set head (first ps)))))
     places)))

; --- the streams ---------------------------------------------------------------

; The bytes rendered for NAME, made by MAKE the first time and kept:
; the key is a symbol, so the lookup is an eq? one.
(def %sd-bytes
  (fn (_ s name make)
    (def key (str->sym name))
    (def hit (Assoc entry key (%sd-get s 6)))
    (if (null? hit)
      ((fn (_ b) (do (%sd-put! s 6 (pair (pair key b) (%sd-get s 6))) b)) (make))
      (rest hit))))

; The turn's stream that is free, or else the one nearest done, cleared.
(def %sd-free-stream
  (fn (_ s)
    (def ls (%sd-get s 3))
    (def best (List fold (fn (_ acc st) (if (int< ((%sd-front s) audio-queued st) ((%sd-front s) audio-queued acc)) st acc)) (first ls) ls))
    (unless (int= 0 ((%sd-front s) audio-queued best)) ((%sd-front s) audio-clear! best))
    best))

; VOICES, each its (gain G) taken to PCT percent of it.
(def %sd-louder
  (fn (_ voices pct)
    (if (int= pct 100) voices
      (List map (fn (_ v) (List map (fn (_ p) (if (if (pair? p) (eq? (first p) (lit gain)) #f) (list (lit gain) (int/ (int* (first (rest p)) pct) 100)) p)) v))
        voices))))

; Sound NAME played now on a turn's stream, at one of three pitches and
; one of three places, -1 left, 0 ahead, 1 right.
(def %sd-play! (fn (_ s name side) (%sd-play-at! s name side 100)))

; Sound NAME played as %sd-play! does at PCT percent of the turn's
; loudness, to the nearest tenth, so that a sound far off is rendered
; at only a few loudnesses.
(def %sd-play-at! (fn (_ s name side pct) (%sd-play-with! s name side 0 pct)))

; Sound NAME played as %sd-play-at! does, CENTS sharper (flatter below
; nought).
(def %sd-play-with!
  (fn (_ s name side cents pct)
    (def set (%sd-get s 0))
    (def f (%sd-sound set name))
    (def vol (int* 10 (int/ (int+ (int/ (int* (%sd-get s 13) pct) 100) 5) 10)))
    (unless (if (null? f) #t (int< vol 1))
      (do (def vary (%sd-prop1 f (lit vary) 0))
          (def pick (int- (%sd-random! s 3) 1))
          (def key (Str8 append name "/" (Str8 str pick) "/" (Str8 str side) "/" (Str8 str vol) "/" (Str8 str cents)))
          (def thin (%sd-get s 26))
          (def key (Str8 append name "/" (Str8 str pick) "/" (Str8 str side) "/" (Str8 str vol) "/" (Str8 str cents)
                                (if (int= thin 0) "" (Str8 append "/" (Str8 str thin)))))
          (def b (%sd-bytes s key
                   (fn (_) (%sd-render (%sd-louder (%sd-voices f (int+ cents (int* pick vary)) (int* side 55)) vol)
                                       (List map rest (%sd-props f (lit echo))) thin))))
          ((%sd-front s) audio-put! (%sd-free-stream s) (first b) (rest b))))))

; The thinning THIN, 0 to 100, as an effect: each frame less THIN percent
; of the frame before, which takes the low end away and leaves the high,
; the more the higher THIN.
(def %sd-thin-spec (fn (_ thin) (list (lit phase) 0 0 1000 0 (int- 0 thin))))

; VOICES with their ECHOES rendered alone, as Mixer render does, through
; the thinning THIN (%sd-thin-spec), none at 0: (REGION . BYTES).
(def %sd-render
  (fn (_ voices echoes thin)
    (if (int= thin 0) (Mixer render %sd-rate voices echoes)
      (do (def m (Mixer make %sd-rate %sd-block))
          (List for-each (fn (_ e) (Mixer echo! m (List ref 0 e) (List ref 1 e) (List ref 2 e))) echoes)
          (Mixer effect! m (lit thin) (%sd-thin-spec thin))
          (Mixer play! m voices 0 100)
          (def prop (fn (_ v key default) ((fn (_ p) (if (null? p) default (rest p)))
                                           (List find (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) v))))
          (def ms (int+ (List fold (fn (_ n e) (int+ n (first e))) 0 echoes)
                        (List fold (fn (_ n v) ((fn (_ t) (if (int< n t) t n))
                                                (int+ (first (prop v (lit at) (list 0))) (first (List ref -1 (prop v (lit env) (lit ((0 100) (200 0)))))))))
                                   0 voices)))
          (def blocks (int+ 1 (int/ (int/ (int* ms %sd-rate) 1000) %sd-block)))
          (def bytes (int* blocks (int* 4 %sd-block)))
          (def out (str-make (int+ bytes 8)))
          ((fn (self i)
             (when (int< i blocks)
               (do (mem-copy (int->ptr (int+ (ptr->int (str->ptr out)) (int* i (int* 4 %sd-block)))) (str->ptr (Mixer block! m)) (int* 4 %sd-block))
                   (self (int+ i 1)))))
           0)
          (pair out bytes)))))

; Sound NAME's voices started in the music, AT frames on, at GAIN percent.
(def %sd-play-in-music! (fn (_ s name side gain at) (%sd-play-into! s (%sd-get s 1) name side gain at)))

; Sound NAME's voices started in mixer M, as %sd-play-in-music! does.
(def %sd-play-into!
  (fn (_ s m name side gain at)
    (def f (%sd-sound (%sd-get s 0) name))
    (unless (null? f)
      (Mixer play! m (%sd-voices f (int* (int- (%sd-random! s 3) 1) (%sd-prop1 f (lit vary) 0)) (int* side 40)) at gain))))

; A number from 0 below N, from the sound's own sequence: the game's
; random source is left as it is, so a seed plays the same game heard or
; not.
(def %sd-random!
  (fn (_ s n)
    (def x (int& (int+ (int* (%sd-get s 9) 1103515245) 12345) 2147483647))
    (%sd-put! s 9 x)
    (int/ (int* (int& (int/ x 65536) 32767) n) 32768)))

; --- tension -------------------------------------------------------------------

(def %sd-clamp (fn (_ n) (if (int< n 0) 0 (if (int< 100 n) 100 n))))

; What there is to fear on G: each creature awake and in sight the more
; the nearer, and the wounds taken past (tension HP-FROM) percent of the
; player's hit points.
(def %sd-tension-of
  (fn (_ s g)
    (def set (%sd-get s 0))
    (def p (game-player g))
    (def near (data-get set (lit tension-near) 12))
    (def threat
      (List fold
        (fn (_ acc cr)
          (if (match ((eq? (creature-state cr) (lit asleep)) #f)
                     ((eq? (creature-state cr) (lit wandering)) #f)
                     (#t (creatures-shown? g cr)))
            (int+ acc (%sd-clamp (int- 100 (int* near (int- (state-dist (player-r p) (player-c p) (creature-r cr) (creature-c cr)) 1)))))
            acc))
        0 (game-creatures g)))
    (def from (data-get set (lit tension-hp) 60))
    (def frac (int/ (int* 100 (player-hp p)) (if (int< (player-hpmax p) 1) 1 (player-hpmax p))))
    (def wounds (if (int< frac from) (int/ (int* 100 (int- from frac)) from) 0))
    (%sd-clamp (if (int< threat wounds) wounds threat))))

; The tension moved toward G's: quickly up, slowly down.
(def %sd-tension!
  (fn (_ s g)
    (def now (%sd-get s 7))
    (def want (%sd-tension-of s g))
    (def next (if (int< now want) (if (int< (int+ now 30) want) (int+ now 30) want)
                (if (int< want (int- now 8)) (int- now 8) want)))
    (%sd-put! s 7 next)
    (unless (null? (%sd-get s 4)) (Tracker tension! (%sd-get s 4) next))
    (unless (null? (%sd-get s 5)) (Tracker tension! (%sd-get s 5) next))))

; The heartbeat as a source of its own mixer, so that nothing done to the
; music (a room, a condition, the thinning) is done to it: off below the
; set's (heart SOUND FROM SLOW FAST) FROM, then SLOW to FAST beats a
; minute and louder as the tension rises to 100.
(def %sd-heart
  (fn (_ s)
    (fn (_ m now)
      (def set (%sd-get s 0))
      (def h (data-one set (lit heart) ()))
      (def t (%sd-get s 7))
      (if (null? h) ()
        (do (def from (List ref 1 h))
            (def bpm (int+ (List ref 2 h) (int/ (int* (int- (List ref 3 h) (List ref 2 h)) t) 100)))
            (when (int< from t)
              (%sd-play-into! s m (first h) 0 (int+ 30 (int/ (int* 70 (int- t from)) (int- 100 from))) 0))
            (int+ now (int/ (int* %sd-rate 60) bpm)))))))

; The place's random sounds as a source, and those a condition or a
; bonus held gives: each (random SOUND EVERY GAIN) or (every SOUND EVERY
; GAIN) heard once in EVERY ms or so, left, ahead or right, at GAIN
; percent.
(def %sd-randoms
  (fn (_ s)
    (fn (_ m now)
      (List for-each
        (fn (_ r)
          (when (int< (%sd-random! s 1000) (int/ 250000 (List ref 1 r)))
            (%sd-play-in-music! s (first r) (int- (%sd-random! s 3) 1) (List ref 2 r) (%sd-random! s (int/ %sd-rate 4)))))
        (List append (%sd-get s 12) (%sd-get s 22)))
      (int+ now (int/ %sd-rate 4)))))

; --- the music for a place -----------------------------------------------------

; The place G's music is for: the band stood in, else the region, else
; default.
(def %sd-place-key
  (fn (_ g)
    (def b (game-band g))
    (match ((not (null? b)) (band-name b))
           ((str=? (game-place g) "") "default")
           (#t (game-place g)))))

; The places G is heard in, the nearest first: the named building whose
; roof is over the player, the interior stood in, then the band, else
; the region, else default.  A building's own song and air are heard
; inside it, and what it lacks is the place's around it.
(def sound-places
  (fn (_ g)
    (def p (game-player g))
    (def m (game-map g))
    (def in (game-inside g))
    (def at (if (int= 0 (map-roof-at m (player-r p) (player-c p))) () (map-place-at m (player-r p) (player-c p))))
    (List append (if (null? at) () (list (first at))) (if (str? in) (list in) ()) (list (%sd-place-key g)))))
(def %sd-same-places?
  (fn (self a b)
    (match ((null? a) (null? b)) ((null? b) #f) ((not (str=? (first a) (first b))) #f) (#t (self (rest a) (rest b))))))

(def %sd-tracker!
  (fn (_ s k song)
    (def t (%sd-get s k))
    (match
      ((null? song) (unless (null? t) (Tracker stop! t)))
      ((null? t) (%sd-put! s k (%sd-tracker-make s song)))
      ((str=? (Tracker name t) (first (rest song))) ())
      (#t (Tracker song! t song)))))

(def %sd-tracker-make
  (fn (_ s song) (Tracker play! (Tracker pace! (Tracker tension! (Tracker make song) (%sd-get s 7)) (List ref 1 (%sd-get s 23))) (%sd-get s 1))))

; The guardian of G's band, on the band's last level and alive, or nil.
(def %sd-guardian
  (fn (_ g)
    (def b (game-band g))
    (def name (if (null? b) "" (if (= (game-depth g) (band-to b)) (band-prop1 b (lit guardian) "") "")))
    (if (str=? name "") () (state-creature-named g name))))

; The guardian S is fighting on G, or nil: one awake and seen, or within
; the set's (boss-near N) cells, is fought until it dies or is left.
(def %sd-boss
  (fn (_ s g)
    (def gd (%sd-guardian g))
    (def p (game-player g))
    (def on
      (match ((null? gd) ())
             ((same? gd (%sd-get s 18)) gd)
             ((eq? (creature-state gd) (lit asleep)) ())
             ((creatures-shown? g gd) gd)
             ((int< (data-get (%sd-get s 0) (lit boss-near) 8)
                    (state-dist (player-r p) (player-c p) (creature-r gd) (creature-c gd))) ())
             (#t gd)))
    (%sd-put! s 18 on)
    on))

; The music G wants: a guardian fought, its (boss NAME SONG); a blow
; struck in the last (fight-turns N) turns, the place's (fight PLACE
; SONG); else the place's (music PLACE SONG), each "default" for the
; rest.  The change is made at once, the song playing stopped and its
; notes left to fade.
(def %sd-music!
  (fn (_ s g)
    (def set (%sd-get s 0))
    (def key (%sd-get s 11))
    (def boss (%sd-boss s g))
    (def wants
      (List filter (fn (_ w) (not (null? w)))
        (list (if (null? boss) () (%sd-for set (lit boss) (list (creature-name boss))))
              (if (int< 0 (%sd-get s 17)) (%sd-for set (lit fight) key) ())
              (%sd-for set (lit music) key))))
    (def song (if (null? wants) () (%sd-song set (List ref 1 (first wants)))))
    (def name (if (null? song) "" (first (rest song))))
    (def t (%sd-get s 4))
    (unless (if (str=? name (%sd-get s 16)) #t (not (null? (game-over g))))
      (do (match
            ((null? song) (do (unless (null? t) (Tracker stop! t)) (%sd-put! s 4 ())))
            (#t (do (unless (null? t) (Tracker stop! t)) (%sd-put! s 4 (%sd-tracker-make s song)))))
          (%sd-put! s 16 name)))))

; Whether a turn has passed on G since S last heard it: a key the game
; held back, at a --More--, passes none, and leaves the last turn's
; blows standing.
(def %sd-turned? (fn (_ s g) (not (= (game-turn g) (%sd-get s 19)))))

; Whether a creature on G is awake, hunting, and in sight.
(def %sd-foes?
  (fn (_ g)
    (List any?
      (fn (_ cr)
        (match ((eq? (creature-state cr) (lit asleep)) #f)
               ((eq? (creature-state cr) (lit wandering)) #f)
               (#t (creatures-shown? g cr))))
      (game-creatures g))))

; The turns left of a fight: the set's (fight-turns N) after a blow
; struck either way; none once no foe is left in sight, the fight won
; or the foe gone; else one fewer each turn without a blow.
(def %sd-fight!
  (fn (_ s g)
    (when (%sd-turned? s g)
      (%sd-put! s 17
        (match ((not (null? (game-blows g))) (data-get (%sd-get s 0) (lit fight-turns) 8))
               ((not (%sd-foes? g)) 0)
               ((int< 0 (%sd-get s 17)) (int- (%sd-get s 17) 1))
               (#t 0))))))

(def %sd-place!
  (fn (_ s g)
    (def key (sound-places g))
    (unless (%sd-same-places? key (%sd-get s 11))
      (do (def set (%sd-get s 0))
          (%sd-put! s 11 key)
          (def amb (%sd-for set (lit ambience) key))
          (def bed (if (null? amb) () (List find (fn (_ p) (if (pair? p) (eq? (first p) (lit bed)) #f)) (rest amb))))
          (%sd-tracker! s 5 (if (null? bed) () (%sd-song set (List ref 1 bed))))
          (%sd-put! s 12 (if (null? amb) ()
                           (List map rest (List filter (fn (_ p) (if (pair? p) (eq? (first p) (lit random)) #f)) (rest amb)))))))))

; --- a turn heard --------------------------------------------------------------

; The names of the bonuses G's player wears, one a ring.
(def %sd-bonuses
  (fn (_ g)
    (List flat-map (fn (_ r) ((fn (_ b) (if (null? b) () (list (symbol->str (first b))))) (item-prop r (lit bonus) ())))
      (player-rings (game-player g)))))

; What of G a turn's sounds are told from: (R C DEPTH HP HPMAX LEVEL
; ITEMS GOLD FOOD CONDITIONS OVER PLACE LAMP CARRIED BONUSES), ITEMS the
; pack's things and CARRIED the count of them, a stack counted as all it
; holds, and BONUSES those worn (%sd-bonuses).
(def %sd-glance
  (fn (_ g)
    (def p (game-player g))
    (list (player-r p) (player-c p) (game-depth g) (player-hp p) (player-hpmax p) (player-level p)
          (List length (game-pack g)) (player-gold p) (player-food p)
          (List map first (player-conditions p)) (game-over g) (%sd-place-key g) (player-lamp p)
          (List fold (fn (_ n it) (int+ n (item-count it))) 0 (game-pack g))
          (%sd-bonuses g))))

; The forms that shape what G's player hears: the set's (condition
; "NAME" PROP ...) for each condition the player is under, and its
; (bonus "NAME" PROP ...) for each bonus worn.
(def %sd-holds
  (fn (_ s g)
    (def set (%sd-get s 0))
    (List append
      (List flat-map (fn (_ c) ((fn (_ f) (if (null? f) () (list f))) (%sd-named set (lit condition) (symbol->str (first c)))))
        (player-conditions (game-player g)))
      (List flat-map (fn (_ b) ((fn (_ f) (if (null? f) () (list f))) (%sd-named set (lit bonus) b)))
        (%sd-bonuses g)))))

; The sound of each of FORMS's (KEY SOUND) props, played ahead.
(def %sd-each!
  (fn (_ s forms key side)
    (List for-each (fn (_ f) (List for-each (fn (_ p) (%sd-play! s (List ref 1 p) side)) (%sd-props f key))) forms)))

; The sounds heard now and again while G's conditions and bonuses hold,
; each (every SOUND EVERY-MS GAIN) of them, and the stomach's growl
; while the player is hungry, kept for the music's source.
(def %sd-held!
  (fn (_ s g)
    (%sd-put! s 22 (List append (List flat-map (fn (_ f) (List map rest (%sd-props f (lit every)))) (%sd-holds s g))
                                (%sd-growl s g)))))

; The set's (growl "SOUND" SLOWEST-MS FASTEST-MS GAIN) as a sound heard
; now and again, (SOUND EVERY GAIN), once the player's food is under the
; set's hungry mark (hunger ...): once in SLOWEST-MS or so there, and
; more often as the food runs out, once in FASTEST-MS with none.  Nil
; when the player is not hungry or the set has no growl.
(def %sd-growl
  (fn (_ s g)
    (def f (data-one (%sd-get s 0) (lit growl) ()))
    (def mark (List ref 1 (game-param g (lit hunger) (list 1300 300 150))))
    (def food (player-food (game-player g)))
    (if (if (null? f) #t (not (int< food mark))) ()
      (list (list (List ref 0 f)
                  (int+ (List ref 2 f) (int/ (int* (int- (List ref 1 f) (List ref 2 f)) (if (int< food 0) 0 food)) (if (int< mark 1) 1 mark)))
                  (List ref 3 f))))))

; How thin the music and the turn's sounds are for the player's wounds,
; 0 to 100: none above the set's (thin-hp FROM MOST) FROM percent of
; their hit points, rising to MOST with none left, by tens so that a
; turn's sounds are rendered at only a few.  0 when the set has none.
(def %sd-thin
  (fn (_ s g)
    (def t (data-one (%sd-get s 0) (lit thin-hp) ()))
    (def p (game-player g))
    (def frac (int/ (int* 100 (if (int< (player-hp p) 0) 0 (player-hp p))) (if (int< (player-hpmax p) 1) 1 (player-hpmax p))))
    (if (if (null? t) #t (not (int< frac (first t)))) 0
      (int* 10 (int/ (int+ (int/ (int* (List ref 1 t) (int- (first t) frac)) (first t)) 5) 10)))))

; The mix G's music and air want, (PITCH PACE CUT EFFECTS SWAY): the
; place's (room PLACE SPEC ...), the nearest place that has one, and
; each condition and bonus held's (pitch CENTS), added, (pace PCT),
; multiplied, (muffle PCT), the least, (effect SPEC), then the thinning
; for the player's wounds (%sd-thin), and (sway PCT PERIOD-MS), the
; widest.  EFFECTS is ((NAME . SPEC) ...), each named by the form it came
; from, the thinning by thin; SWAY is (PCT PERIOD-MS), or nil for none.
(def %sd-mix-want
  (fn (_ s g)
    (def holds (%sd-holds s g))
    (def thin (%sd-thin s g))
    (def all (fn (_ key) (List flat-map (fn (_ f) (%sd-props f key)) holds)))
    (def room (%sd-for (%sd-get s 0) (lit room) (%sd-get s 11)))
    (list (List fold (fn (_ n p) (int+ n (List ref 1 p))) 0 (all (lit pitch)))
          (List fold (fn (_ n p) (int/ (int* n (List ref 1 p)) 100)) 100 (all (lit pace)))
          (List fold (fn (_ n p) (if (int< (List ref 1 p) n) (List ref 1 p) n)) 100 (all (lit muffle)))
          (List append (if (null? room) () (List map (fn (_ e) (pair e e)) (rest room)))
                       (List map (fn (_ p) (pair p (List ref 1 p))) (all (lit effect)))
                       (if (int= thin 0) () (list (pair (lit thin) (%sd-thin-spec thin)))))
          (List fold (fn (_ w p) (if (if (null? w) #t (int< (first w) (List ref 1 p))) (rest p) w)) () (all (lit sway))))))

; The music and air brought to the mix G wants (%sd-mix-want), changing
; only what differs from the mix last set: an effect no longer wanted is
; taken off, and one wanted is put on or changed in its place.  The
; set's music effects (music-effect ...) are kept after every other, so
; a new one is put on before them; the thinning is kept for the turn's
; sounds.  The pace is set again when the sway changes, so one that ends
; leaves the pace as the mix has it; the pump swings it (%sd-sway!).
(def %sd-mix!
  (fn (_ s g)
    (def m (%sd-get s 1))
    (def was (%sd-get s 23))
    (def now (%sd-mix-want s g))
    (%sd-put! s 26 (%sd-thin s g))
    (unless (= (List ref 0 was) (List ref 0 now)) (Mixer pitch! m (List ref 0 now)))
    (unless (if (= (List ref 1 was) (List ref 1 now)) (equal? (List ref 4 was) (List ref 4 now)) #f)
      (List for-each (fn (_ k) (unless (null? (%sd-get s k)) (Tracker pace! (%sd-get s k) (List ref 1 now)))) (list 4 5)))
    (unless (= (List ref 2 was) (List ref 2 now)) (Mixer cut! m (List ref 2 now)))
    (def named (fn (_ es e) (List find (fn (_ x) (same? (first x) (first e))) es)))
    (List for-each (fn (_ e) (when (null? (named (List ref 3 now) e)) (Mixer effect! m (first e) ()))) (List ref 3 was))
    (List for-each
      (fn (_ e) ((fn (_ old) (when (if (null? old) #t (not (equal? (rest old) (rest e)))) (Mixer effect! m (first e) (rest e))))
                 (named (List ref 3 was) e)))
      (List ref 3 now))
    (when (List any? (fn (_ e) (null? (named (List ref 3 was) e))) (List ref 3 now))
      (List for-each (fn (_ e) (do (Mixer effect! m (first e) ()) (Mixer effect! m (first e) (rest e)))) (%sd-get s 27)))
    (%sd-put! s 23 now)))

; The sound of each message key G told this turn that the set gives one,
; (said "KEY" "SOUND"), each key once; a turn's keys are heard once.
(def %sd-said!
  (fn (_ s g)
    (def keys (game-said g))
    (unless (same? keys (%sd-get s 21))
      (do (%sd-put! s 21 keys)
          (List for-each
            (fn (_ k)
              (def f (%sd-named (%sd-get s 0) (lit said) (symbol->str k)))
              (unless (null? f) (%sd-play! s (List ref 1 f) 0)))
            (List fold (fn (_ acc k) (if (List includes? k acc) acc (pair k acc))) () keys))))))

; The sounds of names gone into NOW from WAS, each one's form under HEAD
; giving its (KEY SOUND), or the set's cue FALLBACK.
(def %sd-begun!
  (fn (_ s head was now key fallback)
    (List for-each
      (fn (_ n)
        (unless (List includes? n was)
          (do (def f (%sd-named (%sd-get s 0) head (if (str? n) n (symbol->str n))))
              (if (if (null? f) #t (null? (%sd-props f key))) (unless (null? fallback) (%sd-cue s fallback 0))
                (%sd-each! s (list f) key 0)))))
      now)))

; The cue a change in the purse is heard as, the gold and the count of
; things carried before and after: bought when the gold went down, as
; only a counter takes it; sold when it came up as the pack went down;
; gold when it came up else; nil when it did not change.
(def sound-coin
  (fn (_ gold-was gold-now carried-was carried-now)
    (match ((int< gold-now gold-was) (lit bought))
           ((not (int< gold-was gold-now)) ())
           ((int< carried-now carried-was) (lit sold))
           (#t (lit gold)))))

(def %sd-cue
  (fn (_ s event side)
    (def c (%sd-named (%sd-get s 0) (lit cue) (symbol->str event)))
    (unless (null? c) (%sd-play! s (List ref 1 c) side))))

; Left, ahead or right of the player, by column.
(def %sd-side
  (fn (_ pc c) (match ((int< (int+ c 1) pc) -1) ((int< (int+ pc 1) c) 1) (#t 0))))

(def %sd-terrain-name
  (fn (_ g r c)
    (def t (map-tile (game-map g) r c))
    (def row (List find (fn (_ k) (= (first k) t)) map-terrain))
    (if (null? row) "floor" (symbol->str (List ref 1 row)))))

; The player's step, the terrain's (footstep "TERRAIN" "SOUND"), changed
; by each condition and bonus held's (steps CENTS WANDER PCT): CENTS
; sharper, flatter below nought, heard as far as WANDER percent of a
; side off at random, and at PCT percent.
(def %sd-step!
  (fn (_ s g)
    (def p (game-player g))
    (def f (%sd-named (%sd-get s 0) (lit footstep) (%sd-terrain-name g (player-r p) (player-c p))))
    (def d (%sd-named (%sd-get s 0) (lit footstep) "default"))
    (def hit (if (null? f) d f))
    (def steps (List flat-map (fn (_ h) (List map rest (%sd-props h (lit steps)))) (%sd-holds s g)))
    (def cents (List fold (fn (_ n st) (int+ n (List ref 0 st))) 0 steps))
    (def wander (List fold (fn (_ n st) (if (int< n (List ref 1 st)) (List ref 1 st) n)) 0 steps))
    (def pct (List fold (fn (_ n st) (int/ (int* n (List ref 2 st)) 100)) 100 steps))
    (def side (if (int< (%sd-random! s 100) wander) (int- (int* 2 (%sd-random! s 2)) 1) 0))
    (unless (null? hit) (%sd-play-with! s (List ref 1 hit) side cents pct))))

; The turn's blows: the player's own, a creature's on the player, and
; those between others, each with its cue; a blow that lands on the
; player has each bonus worn's (struck SOUND) too, and one the player
; lands each one's (strikes SOUND).
(def %sd-blows!
  (fn (_ s g)
    (def p (game-player g))
    (def holds (%sd-holds s g))
    (List for-each
      (fn (_ b)
        (def at-player (if (= (List ref 3 b) (player-r p)) (= (List ref 4 b) (player-c p)) #f))
        (def by-player (if (= (List ref 1 b) (player-r p)) (= (List ref 2 b) (player-c p)) #f))
        (def how (List ref 5 b))
        (def lands (if (eq? how (lit hit)) #t (eq? how (lit kill))))
        (if at-player
          (do (%sd-cue s (match ((eq? how (lit miss)) (lit dodged)) (#t (lit struck))) (%sd-side (player-c p) (List ref 2 b)))
              (when lands (%sd-each! s holds (lit struck) (%sd-side (player-c p) (List ref 2 b)))))
          (do (%sd-cue s how (%sd-side (player-c p) (List ref 4 b)))
              (when (if by-player lands #f) (%sd-each! s holds (lit strikes) (%sd-side (player-c p) (List ref 4 b)))))))
      (if (%sd-turned? s g) (game-blows g) ()))))

; G's creatures and how each stands, ((CREATURE . STATE) ...).
(def %sd-states (fn (_ g) (List map (fn (_ cr) (pair cr (creature-state cr))) (game-creatures g))))

; The cry of each creature asleep in WAS, G's creatures before the turn
; (%sd-states), that the turn woke, seen or not: the set's (cry KIND
; SOUND), or its (cry "default" SOUND), quieter by (cry-falloff PCT) a
; cell away, unheard when that comes to nothing.
(def %sd-cries!
  (fn (_ s g was)
    (def set (%sd-get s 0))
    (def p (game-player g))
    (def fall (data-get set (lit cry-falloff) 8))
    (List for-each
      (fn (_ w)
        (def cr (first w))
        (when (if (eq? (rest w) (lit asleep))
                (if (eq? (creature-state cr) (lit asleep)) #f (List any? (fn (_ x) (same? x cr)) (game-creatures g)))
                #f)
          (do (def c (%sd-for set (lit cry) (list (creature-name cr))))
              (def d (state-dist (player-r p) (player-c p) (creature-r cr) (creature-c cr)))
              (def pct (int- 100 (int* fall (int- d 1))))
              (unless (if (null? c) #t (int< pct 1))
                (%sd-play-at! s (List ref 1 c) (%sd-side (player-c p) (creature-c cr)) pct)))))
      was)))

(def %sd-changed!
  (fn (_ s g was now)
    (def at (fn (_ l i) (List ref i l)))
    (def hunger (game-param g (lit hunger) (list 1300 300 150)))
    (def crossed? (fn (_ line) (if (int< line (at was 8)) (not (int< line (at now 8))) #f)))
    (def frac (fn (_ l) (int/ (int* 100 (at l 3)) (if (int< (at l 4) 1) 1 (at l 4)))))
    (def low (data-get (%sd-get s 0) (lit low-hp) 30))
    (match
      ((not (= (at was 2) (at now 2))) (%sd-cue s (lit stairs) 0))
      ((not (if (= (at was 0) (at now 0)) (= (at was 1) (at now 1)) #f)) (%sd-step! s g))
      (#t ()))
    (%sd-blows! s g)
    (when (int< (at now 3) (at was 3))
      (%sd-cue s (if (if (int< (frac now) low) (not (int< (frac was) low)) #f) (lit low) (lit hurt)) 0))
    (when (int< (at was 3) (at now 3))
      (if (int< (int* 4 (int- (at now 3) (at was 3))) (at now 4))
        (%sd-each! s (%sd-holds s g) (lit mends) 0)
        (%sd-cue s (lit healed) 0)))
    (when (int< (at was 5) (at now 5)) (%sd-cue s (lit level) 0))
    (when (int< (at was 6) (at now 6)) (%sd-cue s (lit pickup) 0))
    ((fn (_ coin) (unless (null? coin) (%sd-cue s coin 0))) (sound-coin (at was 7) (at now 7) (at was 13) (at now 13)))
    (when (crossed? (List ref 1 hunger)) (%sd-cue s (lit hungry) 0))
    (when (crossed? (List ref 2 hunger)) (%sd-cue s (lit weak) 0))
    (%sd-begun! s (lit condition) (at was 9) (at now 9) (lit on) (lit afflicted))
    (%sd-begun! s (lit condition) (at now 9) (at was 9) (lit off) (lit relieved))
    (%sd-begun! s (lit bonus) (at was 14) (at now 14) (lit on) ())
    (%sd-begun! s (lit bonus) (at now 14) (at was 14) (lit off) ())
    (%sd-said! s g)
    (unless (str=? (at was 11) (at now 11)) (%sd-cue s (lit arrived) 0))
    (def lamp (game-param g (lit lamp) ()))
    (unless (null? lamp)
      (match ((if (int< (at was 12) 1) (int< 0 (at now 12)) #f) (%sd-cue s (lit lamp-lit) 0))
             ((if (int< 0 (at was 12)) (int< (at now 12) 1) #f) (%sd-cue s (lit lamp-out) 0))
             ((if (int< (List ref 1 lamp) (at was 12)) (not (int< (List ref 1 lamp) (at now 12))) #f) (%sd-cue s (lit lamp-low) 0))
             (#t ())))
    (when (if (null? (at was 10)) (not (null? (at now 10))) #f)
      (do (%sd-cue s (if (eq? (at now 10) (lit won)) (lit won) (lit died)) 0)
          (unless (null? (%sd-get s 4)) (Tracker stop! (%sd-get s 4)))))))

; --- the front end's verbs -----------------------------------------------------

; Sound for game G played through FRONT, Sdl or Web, or nil when there
; is none to be had: no audio device, no compiled loops to keep it fed,
; or a world with no sounds.  The music's echoes are those of the set
; the game began on.  A failure here costs the game its sound and
; nothing else.
(def sound-make
  (fn (_ g front)
    (def set (%sd-forms g))
    (def top (game-top-set g))
    (guard (e ())
      (if (null? (data-all set (lit sound))) ()
        (do (unless (Mixer jit!) (Err raise (lit state) "no compiled mixer" ()))
            (List for-each (fn (_ w) (Mixer wave! (first w) (rest w)))
              (List append (data-all top (lit wave)) (List flat-map (fn (_ r) (data-all (rest r) (lit wave))) (data-all top (lit region)))))
            (def m (Mixer make %sd-rate %sd-block))
            (Mixer gain! m (data-get set (lit music-gain) 80))
            (List for-each (fn (_ e) (Mixer echo! m (List ref 0 e) (List ref 1 e) (List ref 2 e))) (data-all top (lit music-echo)))
            (def heart (Mixer make %sd-rate %sd-block))
            (Mixer gain! heart (data-get set (lit music-gain) 80))
            (List for-each (fn (_ e) (Mixer echo! heart (List ref 0 e) (List ref 1 e) (List ref 2 e))) (data-all top (lit music-echo)))
            (def lasts (List map (fn (_ p) (pair p (first p))) (data-all set (lit music-effect))))
            (List for-each (fn (_ e) (Mixer effect! m (first e) (rest e))) lasts)
            (def s (obj-make %sd-vector-type 30))
            (obj-set! s 0 29)
            (%sd-put! s 28 0)
            (%sd-put! s 24 heart)
            (%sd-put! s 26 0)
            (%sd-put! s 27 lasts)
            (%sd-put! s 21 (game-said g))
            (%sd-put! s 22 ())
            (%sd-put! s 15 front)
            (%sd-put! s 0 set)
            (%sd-put! s 20 (game-set g))
            (%sd-put! s 1 m)
            (%sd-put! s 2 ((%sd-front s) audio-open %sd-rate 2))
            (%sd-put! s 25 ((%sd-front s) audio-open %sd-rate 2))
            (%sd-put! s 3 ((fn (self n) (if (int< n 1) () (pair ((%sd-front s) audio-open %sd-rate 2) (self (int- n 1))))) %sd-effect-streams))
            (%sd-put! s 4 ())
            (%sd-put! s 5 ())
            (%sd-put! s 6 ())
            (%sd-put! s 7 0)
            (%sd-put! s 8 (%sd-glance g))
            (%sd-put! s 9 (int& (game-depth g) 65535))
            (%sd-put! s 10 0)
            (%sd-put! s 11 ())
            (%sd-put! s 12 ())
            (%sd-put! s 13 100)
            (%sd-put! s 14 (%sd-states g))
            (%sd-put! s 16 "")
            (%sd-put! s 17 0)
            (%sd-put! s 18 ())
            (%sd-put! s 19 (game-turn g))
            (%sd-put! s 23 (list 0 100 100 () ()))
            (%sd-tension! s g)
            (%sd-place! s g)
            (%sd-held! s g)
            (%sd-mix! s g)
            (%sd-music! s g)
            (Mixer source! heart (%sd-heart s) 0)
            (Mixer source! m (%sd-randoms s) %sd-rate)
            (sound-pump! s)
            s)))))

; The music's pace swung by the mix's sway (%sd-mix-want), one block
; on: (PCT PERIOD-MS) swings it PCT percent either side of the mix's
; pace and back once in PERIOD-MS, from the pace itself, rising first.
; Slot 28 counts the blocks swung; a tracker's pace is set only when it
; changes.  Nothing without a sway.
(def %sd-sway!
  (fn (_ s)
    (def mix (%sd-get s 23))
    (def sway (List ref 4 mix))
    (unless (null? sway)
      (do (def clock (int+ (%sd-get s 28) 1))
          (%sd-put! s 28 clock)
          (def n (int/ (int/ (int* (List ref 1 sway) %sd-rate) 1000) %sd-block))
          (def period (if (int< n 4) 4 n))
          (def at (int% (int+ clock (int/ period 4)) period))
          (def pct (List ref 0 sway))
          (def half (int/ period 2))
          (def swing (if (int< at half)
                       (int- (int/ (int* (int* 4 pct) at) period) pct)
                       (int- pct (int/ (int* (int* 4 pct) (int- at half)) period))))
          (def pace (int/ (int* (List ref 1 mix) (int+ 100 swing)) 100))
          (List for-each
            (fn (_ k) ((fn (_ t) (unless (null? t) (unless (int= (Tracker pace t) pace) (Tracker pace! t pace)))) (%sd-get s k)))
            (list 4 5))))))

; The music kept ahead of the speaker: blocks rendered and queued until
; it is %sd-ahead bytes ahead.  Answers the blocks rendered.
(def sound-pump!
  (fn (_ s)
    (if (null? s) 0
      ((fn (self n)
         (if (int< ((%sd-front s) audio-queued (%sd-get s 2)) %sd-ahead)
           (do (%sd-sway! s)
               ((%sd-front s) audio-put! (%sd-get s 2) (Mixer block! (%sd-get s 1)) (int* 4 %sd-block))
               ((%sd-front s) audio-put! (%sd-get s 25) (Mixer block! (%sd-get s 24)) (int* 4 %sd-block))
               (%sd-put! s 10 (int+ (%sd-get s 10) 1))
               (self (int+ n 1)))
           n))
       0))))

; Whether the heap wants collecting for the music's sake: true once in so
; many blocks, and the count begun again.
(def sound-collect?
  (fn (_ s)
    (if (null? s) #f
      (if (int< (%sd-get s 10) %sd-collect-blocks) #f (do (%sd-put! s 10 0) #t)))))

; The turn G has just taken, heard: its sounds played, the tension and the
; music brought up to it.
(def sound-turn!
  (fn (_ s g)
    (unless (null? s)
      (do (%sd-world! s g)
          (def now (%sd-glance g))
          (%sd-changed! s g (%sd-get s 8) now)
          (%sd-put! s 8 now)
          (%sd-cries! s g (%sd-get s 14))
          (%sd-put! s 14 (%sd-states g))
          (%sd-tension! s g)
          (%sd-place! s g)
          (%sd-held! s g)
          (%sd-mix! s g)
          (%sd-fight! s g)
          (%sd-music! s g)
          (%sd-put! s 19 (game-turn g))
          (sound-pump! s)))))

; Sound S played with the music at MUSIC percent of the set's own
; (music-gain N) and the turn's sounds at EFFECTS percent; nothing
; heard of either at 0.
(def sound-volume!
  (fn (_ s music effects)
    (unless (null? s)
      (do (List for-each (fn (_ k) (Mixer gain! (%sd-get s k) (int/ (int* music (data-get (%sd-get s 0) (lit music-gain) 80)) 100)))
            (list 1 24))
          (%sd-put! s 13 effects)))))

; The name of the song S last asked for (%sd-music!), "" for none.
(def sound-music (fn (_ s) (if (null? s) "" (%sd-get s 16))))

; The set's cue for EVENT played now, ahead: what the window plays for
; what is no turn, a change of loudness.
(def sound-cue! (fn (_ s event) (unless (null? s) (%sd-cue s event 0))))

(def sound-close
  (fn (_ s)
    (unless (null? s)
      (do ((%sd-front s) audio-close (%sd-get s 2))
          ((%sd-front s) audio-close (%sd-get s 25))
          (List for-each (fn (_ st) ((%sd-front s) audio-close st)) (%sd-get s 3))))))

(provide roguelike/sound sound-make sound-pump! sound-collect? sound-turn! sound-volume! sound-cue! sound-music sound-close
  sound-places sound-coin)
