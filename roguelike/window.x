; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/window.x -- the game played in a window
;
; The same game as the terminal's, drawn by roguelike/paint into a 640
; by 360 screen shown whole in a window, SDL's or a browser tab's (Sdl or
; Web, which answer the same messages), and played with the same
; keys: a key pressed is handed to the game as the terminal would hand
; it, a letter as its string and an arrow, enter or escape by name.
; A gamepad's events become the same keys through roguelike/pad, and
; Alt-Enter switches the window to fullscreen and back.  The mouse
; dragged, or the right stick, moves the view off the player to look
; round; any key brings it back.
; The screen is drawn again after every key, and about twelve times a
; second while a light flickers.  The game is heard as well as seen
; (roguelike/sound): its music is kept fed each time round the loop,
; and each turn's sounds are played as the turn is drawn.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module roguelike/window)

(import x/sys/sdl)
(import x/sys/web)
(import x/sys/posix)
(import x/sys/gc)
(import x/type/vector)
(import x/core/doors int& int+ int- int* int/ int< int= str-make str->ptr ptr-set! str-byte-ref char->int str-byte-len)
(import roguelike/state game-over game-over! game-exploring? game-exploring! game-band band-name game-place game-ask)
(import roguelike/frame frame-art frame-tile-size frame-pan frame-pan!)
(import roguelike/game game-key! game-waiting? game-explore!)
(import roguelike/paint paint-width paint-height paint-make paint-screen paint-turn! paint-view! paint-frame! paint-flickers?
  paint-zoom paint-zoom! paint-animating? paint-step! paint-menu!)
(import roguelike/pad pad-make pad-key pad-event? pad-fullscreen? pad-fullscreen!)
(import roguelike/sound sound-make sound-pump! sound-collect? sound-turn! sound-volume! sound-cue! sound-close)
(import roguelike/menu menu-make menu-chosen menu-key)
(import roguelike/options options-names options-get options-set options-step options-line options-path options-read options-write!)

; A frame's time while a light flickers, drawing it and the wait after,
; and the wait for a key when nothing moves, in microseconds.
(def %wn-frame-us 83000)
; A frame's time while a turn's blows and steps are shown.
(def %wn-step-us 20000)
(def %wn-idle-us 10000)
; The least time of a step while exploring.
(def %wn-explore-us 30000)

; SDL's shift bits, and what a shifted key types on a US keyboard: the
; character after each unshifted one in this string.
(def %wn-shift-mod 3)

; Enter with alt held (option on a Mac) switches the window to fullscreen
; and back, the same key on every system; F11 too where the system lets
; it through (a Mac shows the desktop on it).
(def %wn-f11 1073741892)
(def %wn-alt-mod 768)

; The wall clock in milliseconds, for a held gamepad direction.
(def %wn-ms (fn (_) ((fn (_ t) (+ (* 1000 (first t)) (/ (rest t) 1000))) (Sys time-of-day))))
; A wait of what is left of US microseconds since T0 milliseconds.
(def %wn-rest-of
  (fn (_ us t0)
    ((fn (_ left) (when (int< 0 left) (Sys usleep left))) (int- us (int* 1000 (int- (%wn-ms) t0))))))
(def %wn-shifted "1!2@3#4$5%6^7&8*9(0)-_=+[{]}\\|;:'\",<.>/?`~")

(def %wn-char
  (fn (_ n)
    (def s (str-make 2))
    (ptr-set! (str->ptr s) 0 n 1)
    (ptr-set! (str->ptr s) 1 0 1)
    s))

; The character code CODE types with shift held.
(def %wn-shift
  (fn (_ code)
    (def n (str-byte-len %wn-shifted))
    (def at (fn (_ i) (char->int (str-byte-ref %wn-shifted i))))
    (if (if (int< 96 code) (int< code 123) #f) (- code 32)
      ((fn (self i) (match ((int< n (int+ i 2)) code) ((int= (at i) code) (at (int+ i 1))) (#t (self (int+ i 2))))) 0))))

; The art for game G's place and band, from cache A, [ARTS KEY ART PAD]:
; ARTS answers a place's art (see window-play), KEY is "PLACE/BAND" of
; the art made last, made again only when either changes.
(def %wn-art
  (fn (_ a g)
    (def place (game-place g))
    (def b ((fn (_ b) (if (null? b) () (band-name b))) (game-band g)))
    (def key (Str8 append place "/" (if (str? b) b "")))
    (unless (if (null? (Vector ref 2 a)) #f (str=? key (Vector ref 1 a)))
      (do (Vector set! 1 key a) (Vector set! 2 (frame-art ((Vector ref 0 a) place) b) a)))
    (Vector ref 2 a)))

(def %wn-named
  (list (pair (Sdl key (lit up)) (lit up)) (pair (Sdl key (lit down)) (lit down))
        (pair (Sdl key (lit left)) (lit left)) (pair (Sdl key (lit right)) (lit right))
        (pair 13 (lit enter)) (pair 27 (lit escape)) (pair 8 (lit backspace))))

; An arrow with shift held moves the view a cell, as the right stick
; does: (look DX DY).
(def %wn-looks
  (list (pair (Sdl key (lit up)) (pair 0 -1)) (pair (Sdl key (lit down)) (pair 0 1))
        (pair (Sdl key (lit left)) (pair -1 0)) (pair (Sdl key (lit right)) (pair 1 0))))

; The game's key for SDL keycode CODE with modifiers MOD, or nil for a
; key the game has no use for.
(def window-key
  (fn (_ code mod)
    (def shift? (not (= 0 (int& mod %wn-shift-mod))))
    (def look (if shift? (List find (fn (_ e) (= (first e) code)) %wn-looks) ()))
    (match
      ((match ((= code %wn-f11) #t)
              ((= code 13) (not (= 0 (int& mod %wn-alt-mod))))
              (#t #f))
        (lit fullscreen))
      ((not (null? look)) (list (lit look) (first (rest look)) (rest (rest look))))
      ((if (int< 31 code) (int< code 127) #f)
        (%wn-char (if shift? (%wn-shift code) code)))
      (#t ((fn (_ hit) (if (null? hit) () (rest hit))) (List find (fn (_ e) (= (first e) code)) %wn-named))))))

; The window's cache A: [ARTS KEY ART PAD SOUND OPTIONS PAD? FRONT
; DRAG], ARTS KEY and ART for %wn-art, the gamepad's state, the game's
; sound or nil, the options (roguelike/options), whether the last key
; came from the gamepad, so the prompts show its buttons, the class the
; window is drawn through, Sdl or Web, and the drag under way.
(def %wn-front (fn (_ a) (Vector ref 7 a)))

; The next event of window WIN and the key it is, (EVENT . KEY): a
; gamepad's events go to its state and come back as keys.  Whether the
; key came from the gamepad is kept in A.  A held fullscreen key
; switches once.  The mouse is in the screen's pixels.
(def %wn-input
  (fn (_ a win)
    ; Sdl places the mouse in the screen's pixels given the window; Web
    ; has no mouse.
    (def ev (if (eq? (%wn-front a) Sdl) (Sdl poll win) ((%wn-front a) poll)))
    (def typed? (if (null? ev) #f (eq? (first ev) (lit key-down))))
    (def typed (if typed? (window-key (List ref 1 ev) (List ref 2 ev)) ()))
    (def key (if typed?
               (if (if (eq? typed (lit fullscreen)) (List ref 3 ev) #f) () typed)
               (pad-key (Vector ref 3 a) ev (%wn-ms))))
    (unless (null? key) (Vector set! 6 (not typed?) a))
    (%wn-follow! a ev)
    (pair ev key)))

; SDL's word that window went fullscreen or came back from it, by any
; hand: ours, the system's key for it, or the window's own button.
(def %wn-to-full 535)
(def %wn-from-full 536)

; What window says of fullscreen, in event EV, kept in A's gamepad state
; and options, so the next switch goes the other way from where the
; window is, not from where it was last asked to be.
(def %wn-follow!
  (fn (_ a ev)
    (def to (if (if (null? ev) #f (eq? (first ev) (lit other))) (List ref 1 ev) ()))
    (when (if (null? to) #f (if (int= to %wn-to-full) #t (int= to %wn-from-full)))
      (do (pad-fullscreen! (Vector ref 3 a) (int= to %wn-to-full))
          (%wn-option! a (lit fullscreen) (if (int= to %wn-to-full) 1 0))
          (guard (e ()) (options-write! (Vector ref 5 a) (options-path)))))))
(def %wn-closed? (fn (_ e) (if (null? e) #f (if (eq? (first e) (lit quit)) #t (eq? (first e) (lit close))))))

; The options of A put to work on window WIN, painter P and game G: the
; zoom, fullscreen and how loud the sound is; then kept.
(def %wn-apply!
  (fn (_ a p g win)
    (def o (Vector ref 5 a))
    (def pad (Vector ref 3 a))
    (unless (int= (paint-zoom p) (options-get o (lit zoom)))
      (do (paint-zoom! p (options-get o (lit zoom))) (paint-turn! p g (%wn-art a g))))
    (unless (eq? (pad-fullscreen? pad) (int= 1 (options-get o (lit fullscreen))))
      (do (pad-fullscreen! pad (int= 1 (options-get o (lit fullscreen))))
          ((%wn-front a) fullscreen! win (pad-fullscreen? pad))))
    (if (int= 1 (options-get o (lit mute)))
      (sound-volume! (Vector ref 4 a) 0 0)
      (sound-volume! (Vector ref 4 a) (options-get o (lit music)) (options-get o (lit effects))))
    (guard (e ()) (options-write! o (options-path)))))
(def %wn-option! (fn (_ a name v) (Vector set! 5 (options-set (Vector ref 5 a) name v) a)))

; What KEY asks of the sound: mute for M, -1 for [ (quieter), 1 for ]
; (louder), else nil.
(def %wn-sound-key
  (fn (_ key)
    (if (str? key) (match ((str=? key "M") (lit mute)) ((str=? key "[") -1) ((str=? key "]") 1) (#t ())) ())))

; The sound of A muted or brought back for WHAT mute, else the music and
; the sounds both a step quieter or louder by WHAT, -1 or 1, and heard
; again; the change is kept and put to work, and a louder or quieter one
; is heard at once.
(def %wn-sound!
  (fn (_ a p g win what)
    (if (eq? what (lit mute))
      (%wn-option! a (lit mute) (int- 1 (options-get (Vector ref 5 a) (lit mute))))
      (do (%wn-option! a (lit mute) 0)
          (Vector set! 5 (options-step (options-step (Vector ref 5 a) (lit music) what) (lit effects) what) a)))
    (%wn-apply! a p g win)
    (unless (eq? what (lit mute)) (sound-cue! (Vector ref 4 a) (lit volume)))))

; What the foot of a menu says, as the gamepad's buttons or the keys,
; whichever was used last: ((NAME . WHAT) ...).
(def %wn-prompts
  (fn (_ a values?)
    (def pad? (Vector ref 6 a))
    (List append
      (list (pair (if pad? "A" "Enter") "Choose") (pair (if pad? "B" "Esc") "Back"))
      (if values? (list (pair (if pad? "<>" "Left Right") "Change")) ()))))

; Menu M over game G until a key answers it: what menu-key answered, or
; close when the window is closed.  HEADING, TITLE? and VALUES? as
; paint-menu! and %wn-prompts take them; LINES makes the items' text.
(def %wn-menu
  (fn (self g a p win m heading title? values? lines)
    (def show! (fn (_) ((%wn-front a) show! win (List ref 2 (paint-menu! p g heading title? (lines) (menu-chosen m) (%wn-prompts a values?) (Vector ref 6 a))))))
    (sound-pump! (Vector ref 4 a))
    (def in (%wn-input a win))
    (def ev (first in))
    (def key (rest in))
    (def e (if (pad-event? ev) () ev))
    (def act (if (null? key) () (menu-key m key)))
    (match
      ((%wn-closed? e) (lit close))
      ((eq? key (lit fullscreen))
        (do (%wn-option! a (lit fullscreen) (if (pad-fullscreen? (Vector ref 3 a)) 0 1)) (%wn-apply! a p g win) (show!)
            (self g a p win m heading title? values? lines)))
      ((not (null? act)) act)
      ((not (null? key)) (do (show!) (self g a p win m heading title? values? lines)))
      ((%wn-mouse? e) (self g a p win m heading title? values? lines))
      ((not (null? e)) (do (show!) (self g a p win m heading title? values? lines)))
      ((not (null? ev)) (self g a p win m heading title? values? lines))
      (#t (do (Sys usleep %wn-idle-us)
              (when (sound-collect? (Vector ref 4 a)) (Heap collect))
              (self g a p win m heading title? values? lines))))))

; The options screen over game G until it is left: each option changed
; with left and right, a switch with enter as well, each change put to
; work at once.  Close when the window is closed, else nil.
(def %wn-options
  (fn (self g a p win m)
    (def lines (fn (_) (List append (List map (fn (_ n) (options-line (Vector ref 5 a) n)) options-names) (list "Back"))))
    ((%wn-front a) show! win (List ref 2 (paint-menu! p g "Options" #f (lines) (menu-chosen m) (%wn-prompts a #t) (Vector ref 6 a))))
    (def act (%wn-menu g a p win m "Options" #f #t lines))
    (def step!
      (fn (_ name dir)
        (Vector set! 5 (options-step (Vector ref 5 a) name dir) a)
        (%wn-apply! a p g win)
        (self g a p win m)))
    (match
      ((eq? act (lit close)) act)
      ((eq? act (lit back)) ())
      ((eq? (first act) (lit change)) (if (eq? (first (rest act)) (lit back)) (self g a p win m) (step! (first (rest act)) (rest (rest act)))))
      ((eq? (rest act) (lit back)) ())
      (#t (step! (rest act) 1)))))
(def %wn-options-menu (fn (_) (menu-make (List append (List map (fn (_ n) (pair n "")) options-names) (list (pair (lit back) ""))))))

; The pause over game G: back to it, the options, the keys, or the game
; saved and left.  Close when the window is closed, else nil.
(def %wn-pause
  (fn (self g a p win m)
    (def items (List map rest (Vector ref 0 m)))
    ((%wn-front a) show! win (List ref 2 (paint-menu! p g "Paused" #f items (menu-chosen m) (%wn-prompts a #f) (Vector ref 6 a))))
    (def act (%wn-menu g a p win m "Paused" #f #f (fn (_) items)))
    (def id (if (pair? act) (rest act) ()))
    (match
      ((eq? act (lit close)) act)
      ((eq? act (lit back)) ())
      ((not (eq? (first act) (lit take))) (self g a p win m))
      ((eq? id (lit resume)) ())
      ((eq? id (lit options)) (if (eq? (%wn-options g a p win (%wn-options-menu)) (lit close)) (lit close) (self g a p win m)))
      ((eq? id (lit keys)) (do (game-key! g "?") ()))
      (#t (do (game-over! g (lit saved)) ())))))
(def %wn-pause-items
  (list (pair (lit resume) "Back to the game") (pair (lit options) "Options")
        (pair (lit keys) "Keys") (pair (lit leave) "Save and quit")))

; Game G played in window WIN with art A and painter P until it ends or
; the window is closed; a closed window saves the game.  Escape, when
; nothing is being asked, or a gamepad's Start, pauses it.
(def %wn-loop
  (fn (self g a p win tick)
    (def pad (Vector ref 3 a))
    (def snd (Vector ref 4 a))
    (sound-pump! snd)
    (def in (%wn-input a win))
    (def ev (first in))
    ; A gamepad's A goes on past a message as enter does.
    (def key (if (if (Vector ref 6 a) (if (str? (rest in)) (if (str=? (rest in) ",") (game-waiting? g) #f) #f) #f)
               (lit enter)
               (rest in)))
    (def e (if (pad-event? ev) () ev))
    (match
      ((not (null? (game-over g))) ())
      ((%wn-closed? e) (game-over! g (lit saved)))
      ((eq? key (lit fullscreen))
        (do (%wn-option! a (lit fullscreen) (if (pad-fullscreen? pad) 0 1))
            (%wn-apply! a p g win)
            ((%wn-front a) show! win (List ref 2 (paint-screen p)))
            (self g a p win tick)))
      ((if (eq? key (lit pause)) #t (if (eq? key (lit escape)) (null? (game-ask g)) #f))
        (do (when (eq? (%wn-pause g a p win (menu-make %wn-pause-items)) (lit close)) (game-over! g (lit saved)))
            (paint-turn! p g (%wn-art a g))
            ((%wn-front a) show! win (List ref 2 (paint-frame! p g tick)))
            (self g a p win tick)))
      ; + or = shows the level larger, - smaller: the window's, not the
      ; game's, so no turn passes.
      ((not (int= 0 (%wn-zoom-step key)))
        (do (%wn-option! a (lit zoom) (int+ (paint-zoom p) (%wn-zoom-step key)))
            (%wn-apply! a p g win)
            ((%wn-front a) show! win (List ref 2 (paint-frame! p g tick)))
            (Heap collect)
            (self g a p win tick)))
      ; M mutes the sound or brings it back, [ and ] make it quieter and
      ; louder: the window's too, so no turn passes.
      ((if (null? (%wn-sound-key key)) #f (null? (game-ask g)))
        (do (%wn-sound! a p g win (%wn-sound-key key))
            (self g a p win tick)))
      ; The right stick moves the view a cell; the window's, so no turn
      ; passes.
      ((if (pair? key) (eq? (first key) (lit look)) #f)
        (do (%wn-pan! a p g win tick (int+ (first (frame-pan)) (List ref 2 key)) (int+ (rest (frame-pan)) (List ref 1 key)))
            (self g a p win tick)))
      ; The mouse drags the view.
      ((%wn-mouse? e) (do (%wn-drag! a p g win tick e) (self g a p win tick)))
      ; The frame goes on screen before the heap is collected: the
      ; collect's cost comes after the key's answer, not before it.  A
      ; key brings a dragged view back to the player.
      ((not (null? key))
        (do (frame-pan! g 0 0)
            (if (game-exploring? g) (game-exploring! g ()) (game-key! g key))
            (sound-turn! snd g)
            (%wn-turn-shown! a p g win snd tick)
            (self g a p win tick)))
      ; Any other event -- a resize, the window shown again -- may have
      ; lost what was presented: the frame is presented again.
      ((not (null? e)) (do ((%wn-front a) show! win (List ref 2 (paint-screen p))) (self g a p win tick)))
      ; A gamepad event that is no key yet: the next one at once.
      ((not (null? ev)) (self g a p win tick))
      ; Exploring steps on without waiting for each step to be shown, a
      ; step at least %wn-explore-us long.
      ((game-exploring? g)
        (do (def t0 (%wn-ms))
            (frame-pan! g 0 0)
            (game-explore! g)
            (sound-turn! snd g)
            (%wn-turn-shown! a p g win snd tick)
            (%wn-rest-of %wn-explore-us t0)
            (self g a p win tick)))
      ; A turn's blows and steps shown a frame at a time, before anything
      ; else moves; a key pressed meanwhile is taken at once.
      ; Each waits only what drawing the frame left of its time.
      ((paint-animating? p)
        (do (def t0 (%wn-ms))
            (paint-step! p)
            ((%wn-front a) show! win (List ref 2 (paint-frame! p g (+ tick 1))))
            (%wn-rest-of %wn-step-us t0)
            (self g a p win (+ tick 1))))
      ((paint-flickers? p)
        (do (def t0 (%wn-ms))
            ((%wn-front a) show! win (List ref 2 (paint-frame! p g (+ tick 1))))
            (Heap collect)
            (%wn-rest-of %wn-frame-us t0)
            (self g a p win (+ tick 1))))
      (#t (do (Sys usleep %wn-idle-us)
              (when (sound-collect? snd) (Heap collect))
              (self g a p win tick))))))

; The turn game G has just taken drawn and shown at TICK, the heap
; collected after: the music topped up before each of the three, each
; long enough to empty what is queued of it while a busy machine takes
; its share.
(def %wn-turn-shown!
  (fn (_ a p g win snd tick)
    (sound-pump! snd)
    (paint-turn! p g (%wn-art a g))
    (sound-pump! snd)
    ((%wn-front a) show! win (List ref 2 (paint-frame! p g tick)))
    (sound-pump! snd)
    (Heap collect)))

; --- dragging the view ---------------------------------------------------------

(def %wn-mouse?
  (fn (_ e) (if (null? e) #f (if (List find (fn (_ k) (eq? k (first e))) (lit (mouse-down mouse-up mouse-motion))) #t #f))))

; Game G's view moved to DR DC cells off the player, held to the map,
; and shown at TICK when it moved: drawn again without the turn's blows
; and steps.
(def %wn-pan!
  (fn (_ a p g win tick dr dc)
    (def was (frame-pan))
    (frame-pan! g dr dc)
    (unless (equal? was (frame-pan))
      (do (paint-view! p g (%wn-art a g))
          (sound-pump! (Vector ref 4 a))
          ((%wn-front a) show! win (List ref 2 (paint-frame! p g tick)))))))

; Mouse event E taken: the left button down starts a drag, kept in A as
; (X Y DR DC), where it went down and the view's pan then; a motion
; with the left button held moves the view by the whole cells the
; mouse has gone, the level following the hand; the button up ends it.
(def %wn-drag!
  (fn (_ a p g win tick e)
    (def d (Vector ref 8 a))
    (def t (int* frame-tile-size (paint-zoom p)))
    ; Pixels to the nearest whole cells.
    (def cells (fn (_ px) (int/ (int+ px (if (int< px 0) (int- 0 (int/ t 2)) (int/ t 2))) t)))
    (match
      ((eq? (first e) (lit mouse-down))
        (when (eq? (List ref 1 e) (lit left))
          (Vector set! 8 (list (List ref 2 e) (List ref 3 e) (first (frame-pan)) (rest (frame-pan))) a)))
      ((eq? (first e) (lit mouse-up)) (when (eq? (List ref 1 e) (lit left)) (Vector set! 8 () a)))
      ((null? d) ())
      ((not (List find (fn (_ b) (eq? b (lit left))) (List ref 3 e))) (Vector set! 8 () a))
      (#t (%wn-pan! a p g win tick
            (int+ (List ref 2 d) (cells (int- (List ref 1 d) (List ref 2 e))))
            (int+ (List ref 3 d) (cells (int- (List ref 0 d) (List ref 1 e)))))))))

; The zoom KEY asks for: 1 for + or =, -1 for -, 0 for any other.
(def %wn-zoom-step
  (fn (_ key)
    (if (str? key) (match ((str=? key "+") 1) ((str=? key "=") 1) ((str=? key "-") -1) (#t 0)) 0)))

; The title screen over game G, the game a new one starts with, until
; one is chosen: (play . G) for the game to play -- SAVED, or G when
; there is none or a new one is asked for, made by FRESH when G is
; SAVED -- or nil to leave.  TITLE is the set's.
(def %wn-title
  (fn (self g saved fresh a p win m title)
    (def items (List map rest (Vector ref 0 m)))
    ((%wn-front a) show! win (List ref 2 (paint-menu! p g title #t items (menu-chosen m) (%wn-prompts a #f) (Vector ref 6 a))))
    (def act (%wn-menu g a p win m title #t #f (fn (_) items)))
    (def id (if (pair? act) (rest act) ()))
    (match
      ((eq? act (lit close)) ())
      ((not (pair? act)) (self g saved fresh a p win m title))
      ((not (eq? (first act) (lit take))) (self g saved fresh a p win m title))
      ((eq? id (lit continue)) (pair (lit play) g))
      ((eq? id (lit new))
        (if (null? saved) (pair (lit play) g)
          (do (def n (fresh))
              (sound-close (Vector ref 4 a))
              (Vector set! 4 (sound-make n (%wn-front a)) a)
              (%wn-apply! a p n win)
              (paint-turn! p n (%wn-art a n))
              (pair (lit play) n))))
      ((eq? id (lit options))
        (if (eq? (%wn-options g a p win (%wn-options-menu)) (lit close)) ()
          (self g saved fresh a p win m title)))
      (#t ()))))

; A game played in a window: the title screen first, over the game a
; new one would start with, offering the game SAVED (nil for none),
; a new one from FRESH, the options, or leaving.  The art from ARTS and
; FONT (from paint-font), at SCALE times the screen's size, the level
; at ZOOM, nil for the options'.  ARTS takes a place, "" for the set
; the game began on or a region's name (game-place), and answers that
; place's art (from paint-art), so each region is drawn with its own
; set's pictures; TITLE heads the title screen.  Answers (G . FAILED):
; the game played, nil when none was, and nil or what was raised while
; it was played, the window closed either way.  FRONT is the class the
; window is drawn through, Sdl or Web.
(def window-play
  (fn (_ front saved fresh arts font scale zoom title)
    (def o (options-read (options-path)))
    (def a (Vector of arts "" () (pad-make) () (if (null? zoom) o (options-set o (lit zoom) zoom)) #f front ()))
    ; Fullscreen on a Mac stays on the desktop's Space: a Space of its
    ; own slides in, and a switch back before the slide ends leaves an
    ; empty screen with the window gone.
    (when (eq? front Sdl) (Sdl hint! "SDL_VIDEO_MAC_FULLSCREEN_SPACES" "0"))
    (def win (front scaling! (front open title paint-width paint-height scale) (lit fit)))
    (def played (Vector of ()))
    (def failed
      (guard (e e)
        (do (def p (paint-make font))
            (def g (if (null? saved) (fresh) saved))
            (Vector set! 4 (sound-make g front) a)
            (paint-zoom! p (options-get (Vector ref 5 a) (lit zoom)))
            (paint-turn! p g (%wn-art a g))
            (%wn-apply! a p g win)
            (def chosen
              (%wn-title g saved fresh a p win
                (menu-make (List append (if (null? saved) () (list (pair (lit continue) "Continue")))
                             (list (pair (lit new) "New game") (pair (lit options) "Options") (pair (lit quit) "Quit"))))
                title))
            (unless (null? chosen)
              (do (Vector set! 0 (rest chosen) played)
                  (paint-turn! p (rest chosen) (%wn-art a (rest chosen)))
                  ((%wn-front a) show! win (List ref 2 (paint-frame! p (rest chosen) 0)))
                  (%wn-loop (rest chosen) a p win 0)))
            ())))
    (sound-close (Vector ref 4 a))
    (front close win)
    (pair (Vector ref 0 played) failed)))

(provide roguelike/window window-key window-play)
