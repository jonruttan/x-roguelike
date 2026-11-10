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
; up or down the stairs, into a new band, the lamp lit, low or out.  A
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

(import x/sys/sdl)
(import x/audio/mixer)
(import x/audio/tracker)
(import x/core/doors int* int+ int- int/ int< int= int& obj-make obj-ref obj-set!)
(import roguelike/data data-all data-one data-get)
(import roguelike/state game-set game-player game-depth game-map game-creatures game-pack game-over game-blows game-turn
  game-band band-name game-place game-below? game-param player-r player-c player-hp player-hpmax player-level player-gold
  player-food player-lamp player-conditions creature-r creature-c creature-state creature-name state-dist state-ring?
  band-to band-prop1 state-creature-named)
(import roguelike/map map-tile map-terrain)
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
; A vector: 0 the set, 1 the mixer, 2 the music's stream, 3 the turn's
; streams, 4 the music's tracker, 5 the bed's, 6 the sounds rendered,
; ((KEY . (REGION . BYTES)) ...), 7 the tension, 8 the game as it was
; (%sd-glance), 9 the random state, 10 blocks since a collect, 11 the
; place the music is for, 12 the place's random sounds, 13 how loud
; the turn's sounds are, a percentage (sound-volume!), 14 the creatures
; as they stood (%sd-states), 15 and 16 the rank and name of the song
; last asked for (%sd-music!), 17 the turns left of a fight, 18 the
; guardian fought, or nil, 19 the game's turn last heard (%sd-turned?).

(def %sd-vector-type ((prim-ref (lit type) (lit of)) (Vector make 0 ())))
(def %sd-get (fn (_ s k) (obj-ref s (int+ k 1))))
(def %sd-put! (fn (_ s k x) (obj-set! s (int+ k 1) x)))

; --- the set's data ------------------------------------------------------------

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

; What PLACE plays, from (music PLACE SONG) and (ambience PLACE (bed SONG)
; (random SOUND EVERY-MS GAIN) ...), PLACE a band's name, a region's,
; or default.
(def %sd-for
  (fn (_ set head place)
    ((fn (_ hit) (if (null? hit) (%sd-named set head "default") hit)) (%sd-named set head place))))

; --- the streams ---------------------------------------------------------------

(def %sd-bytes
  (fn (_ s key make)
    (def hit (Assoc entry key (%sd-get s 6)))
    (if (null? hit)
      ((fn (_ b) (do (%sd-put! s 6 (pair (pair key b) (%sd-get s 6))) b)) (make))
      (rest hit))))

; The turn's stream that is free, or else the one nearest done, cleared.
(def %sd-free-stream
  (fn (_ s)
    (def ls (%sd-get s 3))
    (def best (List fold (fn (_ acc st) (if (int< (Sdl audio-queued st) (Sdl audio-queued acc)) st acc)) (first ls) ls))
    (unless (int= 0 (Sdl audio-queued best)) (Sdl audio-clear! best))
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
(def %sd-play-at!
  (fn (_ s name side pct)
    (def set (%sd-get s 0))
    (def f (%sd-sound set name))
    (def vol (int* 10 (int/ (int+ (int/ (int* (%sd-get s 13) pct) 100) 5) 10)))
    (unless (if (null? f) #t (int< vol 1))
      (do (def vary (%sd-prop1 f (lit vary) 0))
          (def pick (int- (%sd-random! s 3) 1))
          (def key (Str8 append name "/" (Str8 str pick) "/" (Str8 str side) "/" (Str8 str vol)))
          (def b (%sd-bytes s key
                   (fn (_) (Mixer render %sd-rate (%sd-louder (%sd-voices f (int* pick vary) (int* side 55)) vol)
                                     (List map rest (%sd-props f (lit echo)))))))
          (Sdl audio-put! (%sd-free-stream s) (first b) (rest b))))))

; Sound NAME's voices started in the music, AT frames on, at GAIN percent.
(def %sd-play-in-music!
  (fn (_ s name side gain at)
    (def f (%sd-sound (%sd-get s 0) name))
    (unless (null? f)
      (Mixer play! (%sd-get s 1) (%sd-voices f (int* (int- (%sd-random! s 3) 1) (%sd-prop1 f (lit vary) 0)) (int* side 40)) at gain))))

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
  (fn (_ g)
    (def set (game-set g))
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
    (def want (%sd-tension-of g))
    (def next (if (int< now want) (if (int< (int+ now 30) want) (int+ now 30) want)
                (if (int< want (int- now 8)) (int- now 8) want)))
    (%sd-put! s 7 next)
    (unless (null? (%sd-get s 4)) (Tracker tension! (%sd-get s 4) next))
    (unless (null? (%sd-get s 5)) (Tracker tension! (%sd-get s 5) next))))

; The heartbeat as a source of the music: off below the set's (heart
; SOUND FROM SLOW FAST) FROM, then SLOW to FAST beats a minute and louder
; as the tension rises to 100.
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
              (%sd-play-in-music! s (first h) 0 (int+ 30 (int/ (int* 70 (int- t from)) (int- 100 from))) 0))
            (int+ now (int/ (int* %sd-rate 60) bpm)))))))

; The place's random sounds as a source: each (random SOUND EVERY GAIN)
; heard once in EVERY ms or so, left, ahead or right, at GAIN percent.
(def %sd-randoms
  (fn (_ s)
    (fn (_ m now)
      (List for-each
        (fn (_ r)
          (when (int< (%sd-random! s 1000) (int/ 250000 (List ref 1 r)))
            (%sd-play-in-music! s (first r) (int- (%sd-random! s 3) 1) (List ref 2 r) (%sd-random! s (int/ %sd-rate 4)))))
        (%sd-get s 12))
      (int+ now (int/ %sd-rate 4)))))

; --- the music for a place -----------------------------------------------------

(def %sd-place-key
  (fn (_ g)
    (def b (game-band g))
    (if (game-below? g) (game-place g) (if (null? b) "default" (band-name b)))))

(def %sd-tracker!
  (fn (_ s k song)
    (def t (%sd-get s k))
    (match
      ((null? song) (unless (null? t) (Tracker stop! t)))
      ((null? t) (%sd-put! s k (%sd-tracker-make s song)))
      ((str=? (Tracker name t) (first (rest song))) ())
      (#t (Tracker song! t song)))))

(def %sd-tracker-make
  (fn (_ s song) (Tracker play! (Tracker tension! (Tracker make song) (%sd-get s 7)) (%sd-get s 1))))

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
; rest.  A louder one starts at once, cutting in; a quieter one waits
; for the pattern playing to end.
(def %sd-music!
  (fn (_ s g)
    (def set (%sd-get s 0))
    (def key (%sd-get s 11))
    (def boss (%sd-boss s g))
    (def wants
      (List filter (fn (_ w) (not (null? (rest w))))
        (list (pair 2 (if (null? boss) () (%sd-for set (lit boss) (creature-name boss))))
              (pair 1 (if (int< 0 (%sd-get s 17)) (%sd-for set (lit fight) key) ()))
              (pair 0 (%sd-for set (lit music) key)))))
    (def rank (if (null? wants) 0 (first (first wants))))
    (def song (if (null? wants) () (%sd-song set (List ref 1 (rest (first wants))))))
    (def name (if (null? song) "" (first (rest song))))
    (def t (%sd-get s 4))
    (unless (if (str=? name (%sd-get s 16)) #t (not (null? (game-over g))))
      (do (match
            ((null? song) (do (unless (null? t) (Tracker stop! t)) (%sd-put! s 4 ())))
            ((if (null? t) #t (int< (%sd-get s 15) rank))
              (do (unless (null? t) (Tracker stop! t)) (%sd-put! s 4 (%sd-tracker-make s song))))
            (#t (Tracker song! t song)))
          (%sd-put! s 15 rank)
          (%sd-put! s 16 name)))))

; Whether a turn has passed on G since S last heard it: a key the game
; held back, at a --More--, passes none, and leaves the last turn's
; blows standing.
(def %sd-turned? (fn (_ s g) (not (= (game-turn g) (%sd-get s 19)))))

; The turns left of a fight: the set's (fight-turns N) after a blow
; struck either way, one fewer each turn without.
(def %sd-fight!
  (fn (_ s g)
    (when (%sd-turned? s g)
      (%sd-put! s 17
        (if (null? (game-blows g))
          (if (int< 0 (%sd-get s 17)) (int- (%sd-get s 17) 1) 0)
          (data-get (%sd-get s 0) (lit fight-turns) 8))))))

(def %sd-place!
  (fn (_ s g)
    (def key (%sd-place-key g))
    (unless (str=? key (%sd-get s 11))
      (do (def set (%sd-get s 0))
          (%sd-put! s 11 key)
          (def amb (%sd-for set (lit ambience) key))
          (def bed (if (null? amb) () (List find (fn (_ p) (if (pair? p) (eq? (first p) (lit bed)) #f)) (rest amb))))
          (%sd-tracker! s 5 (if (null? bed) () (%sd-song set (List ref 1 bed))))
          (%sd-put! s 12 (if (null? amb) ()
                           (List map rest (List filter (fn (_ p) (if (pair? p) (eq? (first p) (lit random)) #f)) (rest amb)))))))))

; --- a turn heard --------------------------------------------------------------

; What of G a turn's sounds are told from: (R C DEPTH HP HPMAX LEVEL
; ITEMS GOLD FOOD CONDITIONS OVER PLACE LAMP).
(def %sd-glance
  (fn (_ g)
    (def p (game-player g))
    (list (player-r p) (player-c p) (game-depth g) (player-hp p) (player-hpmax p) (player-level p)
          (List length (game-pack g)) (player-gold p) (player-food p)
          (List map first (player-conditions p)) (game-over g) (%sd-place-key g) (player-lamp p))))

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

(def %sd-step!
  (fn (_ s g)
    (def p (game-player g))
    (def f (%sd-named (%sd-get s 0) (lit footstep) (%sd-terrain-name g (player-r p) (player-c p))))
    (def d (%sd-named (%sd-get s 0) (lit footstep) "default"))
    (def hit (if (null? f) d f))
    (unless (null? hit)
      (%sd-play-at! s (List ref 1 hit) 0 (if (state-ring? g (lit stealth)) (data-get (%sd-get s 0) (lit stealth-steps) 40) 100)))))

(def %sd-blows!
  (fn (_ s g)
    (def p (game-player g))
    (List for-each
      (fn (_ b)
        (def at-player (if (= (List ref 3 b) (player-r p)) (= (List ref 4 b) (player-c p)) #f))
        (def how (List ref 5 b))
        (if at-player
          (%sd-cue s (match ((eq? how (lit miss)) (lit dodged)) (#t (lit struck))) (%sd-side (player-c p) (List ref 2 b)))
          (%sd-cue s how (%sd-side (player-c p) (List ref 4 b)))))
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
          (do (def c (%sd-for set (lit cry) (creature-name cr)))
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
      (unless (int< (int* 4 (int- (at now 3) (at was 3))) (at now 4)) (%sd-cue s (lit healed) 0)))
    (when (int< (at was 5) (at now 5)) (%sd-cue s (lit level) 0))
    (when (int< (at was 6) (at now 6)) (%sd-cue s (lit pickup) 0))
    (when (int< (at was 7) (at now 7)) (%sd-cue s (lit gold) 0))
    (when (crossed? (List ref 1 hunger)) (%sd-cue s (lit hungry) 0))
    (when (crossed? (List ref 2 hunger)) (%sd-cue s (lit weak) 0))
    (unless (List all? (fn (_ c) (List includes? c (at was 9))) (at now 9)) (%sd-cue s (lit afflicted) 0))
    (unless (List all? (fn (_ c) (List includes? c (at now 9))) (at was 9)) (%sd-cue s (lit relieved) 0))
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

; Sound for game G, or nil when there is none to be had: no audio device,
; no compiled loops to keep it fed, or a set with no sounds.  A failure
; here costs the game its sound and nothing else.
(def sound-make
  (fn (_ g)
    (def set (game-set g))
    (guard (e ())
      (if (null? (data-all set (lit sound))) ()
        (do (unless (Mixer jit!) (Err raise (lit state) "no compiled mixer" ()))
            (List for-each (fn (_ w) (Mixer wave! (first w) (rest w))) (data-all set (lit wave)))
            (def m (Mixer make %sd-rate %sd-block))
            (Mixer gain! m (data-get set (lit music-gain) 80))
            (List for-each (fn (_ e) (Mixer echo! m (List ref 0 e) (List ref 1 e) (List ref 2 e))) (data-all set (lit music-echo)))
            (def s (obj-make %sd-vector-type 21))
            (obj-set! s 0 20)
            (%sd-put! s 0 set)
            (%sd-put! s 1 m)
            (%sd-put! s 2 (Sdl audio-open %sd-rate 2))
            (%sd-put! s 3 ((fn (self n) (if (int< n 1) () (pair (Sdl audio-open %sd-rate 2) (self (int- n 1))))) %sd-effect-streams))
            (%sd-put! s 4 ())
            (%sd-put! s 5 ())
            (%sd-put! s 6 ())
            (%sd-put! s 7 0)
            (%sd-put! s 8 (%sd-glance g))
            (%sd-put! s 9 (int& (game-depth g) 65535))
            (%sd-put! s 10 0)
            (%sd-put! s 11 "")
            (%sd-put! s 12 ())
            (%sd-put! s 13 100)
            (%sd-put! s 14 (%sd-states g))
            (%sd-put! s 15 0)
            (%sd-put! s 16 "")
            (%sd-put! s 17 0)
            (%sd-put! s 18 ())
            (%sd-put! s 19 (game-turn g))
            (%sd-tension! s g)
            (%sd-place! s g)
            (%sd-music! s g)
            (Mixer source! m (%sd-heart s) 0)
            (Mixer source! m (%sd-randoms s) %sd-rate)
            (sound-pump! s)
            s)))))

; The music kept ahead of the speaker: blocks rendered and queued until
; it is %sd-ahead bytes ahead.  Answers the blocks rendered.
(def sound-pump!
  (fn (_ s)
    (if (null? s) 0
      ((fn (self n)
         (if (int< (Sdl audio-queued (%sd-get s 2)) %sd-ahead)
           (do (Sdl audio-put! (%sd-get s 2) (Mixer block! (%sd-get s 1)) (int* 4 %sd-block))
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
      (do (def now (%sd-glance g))
          (%sd-changed! s g (%sd-get s 8) now)
          (%sd-put! s 8 now)
          (%sd-cries! s g (%sd-get s 14))
          (%sd-put! s 14 (%sd-states g))
          (%sd-tension! s g)
          (%sd-place! s g)
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
      (do (Mixer gain! (%sd-get s 1) (int/ (int* music (data-get (%sd-get s 0) (lit music-gain) 80)) 100))
          (%sd-put! s 13 effects)))))

; The name of the song S last asked for (%sd-music!), "" for none.
(def sound-music (fn (_ s) (if (null? s) "" (%sd-get s 16))))

; The set's cue for EVENT played now, ahead: what the window plays for
; what is no turn, a change of loudness.
(def sound-cue! (fn (_ s event) (unless (null? s) (%sd-cue s event 0))))

(def sound-close
  (fn (_ s)
    (unless (null? s)
      (do (Sdl audio-close (%sd-get s 2))
          (List for-each (fn (_ st) (Sdl audio-close st)) (%sd-get s 3))))))

(provide roguelike/sound sound-make sound-pump! sound-collect? sound-turn! sound-volume! sound-cue! sound-music sound-close)
