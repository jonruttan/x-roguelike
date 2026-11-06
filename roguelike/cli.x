; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/cli.x -- the command line, and the terminal
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
; lint-known: %lang-root
;
;   x -l roguelike -- [-s NAME] [-S N] [-d DIR] [play]   a game
;   x -l roguelike -- scores                            the best games
;
; The options are one declaration to the platform's Opts, which parses
; them and prints the help.  The set is a directory of .xon files under
; the bundle's data/, or any directory given to --data.  Playing takes
; the terminal: raw, on the
; alternate screen, the cursor on the player, given back as it was on
; the way out.  A game is saved by S and taken up again by the next
; play; a finished game goes to the scores.

(module roguelike/cli)

(import x/type/vector)
(import x/sys/posix)
(import x/sys/file)
(import x/sys/gc)
(import x/repl/term)
(import x/tui/screen)
(import x/sys/opts)
(import roguelike/data data-load data-get)
(import roguelike/state
  game-over game-epitaph game-depth game-deepest game-messages game-ask game-player player-gold game-exploring? game-exploring!)
(import roguelike/game game-make game-key! game-explore! game-score game-help)
(import roguelike/draw game-draw!)
(import roguelike/save save-write! save-read save-path save-score! save-scores)

(def roguelike-version "0.1.0")

; The options and the help text, one declaration: what parse accepts is
; what usage prints.
(def roguelike-options
  (Opts declare "x -l roguelike --" "[OPTIONS] [play | scores]"
    "A roguelike: a dungeon crawl whose creatures, items and messages are a set of .xon files.\nWith no word, or play, a game; scores lists the best games.  Playing, ? lists the keys."
    (list (Opts arg "-s" "--set" "NAME" "The set to play: classic, delve, or a directory under data/")
          (Opts arg "-S" "--seed" "N" "The seed; the same seed is the same dungeon")
          (Opts arg "-d" "--data" "DIR" "Where the sets are, in place of the bundle's data/")
          (Opts flag "-V" "--version" "Print the version and exit")
          (Opts flag "-h" "--help" "Print this help and exit"))
    (pair (lit help) #f)))

(def %cl-say (fn (_ fd text) (Sys fd-write fd text)))
(def %cl-to-int
  (fn (_ s) (guard (e ()) ((prim-ref (lit convert) (lit to)) s (Type named INTEGER) 10))))

; Where the sets are: --data, X_ROGUELIKE_DATA, the installed bundle's
; data/, or data/ here.
(def %cl-data-dir
  (fn (_ opts)
    (def env (Sys getenv "X_ROGUELIKE_DATA"))
    (def root (guard (e ()) %lang-root))
    (match ((not (null? (Opts value opts "-d"))) (Opts value opts "-d"))
           ((if (null? env) #f (not (str=? env ""))) env)
           ((str? root) (Str8 append root "/data"))
           (#t "data"))))

(def %cl-err-text
  (fn (_ e)
    (match ((Err err? e) (e msg))
           ((str? e) e)
           (#t (Err code-of e)))))

; --- the terminal ------------------------------------------------------------

; A byte reader for Term key: bytes read sixty-four at a time and handed
; out one by one; asked anything, whether any are in hand.  After an
; Escape with none in hand it waits thirty milliseconds for more, and
; answers nil when none come, which the decoder takes as a bare Escape
; rather than the start of a sequence.
(def %cl-reader
  (fn (_)
    (def box (Vector of () #f))
    (def waiting? (fn (_) (not (null? (Sys poll (list (pair 0 (list (lit in)))) 30)))))
    (fn (self . ask)
      (if (not (null? ask)) (not (null? (Vector ref 0 box)))
        (do (when (if (null? (Vector ref 0 box)) (if (Vector ref 1 box) (waiting?) #t) #f)
              (Vector set! 0 (Sys fd-read 0 64) box))
            (def b (if (null? (Vector ref 0 box)) () (first (Vector ref 0 box))))
            (unless (null? b) (Vector set! 0 (rest (Vector ref 0 box)) box))
            (Vector set! 1 (if (null? b) #f (= b 27)) box)
            b)))))

(def %cl-show!
  (fn (_ g screen)
    (game-draw! g screen)
    (Term emit 1 (Screen render screen))))

; Whether a key is waiting: in the reader's hand, or at the terminal
; within MS milliseconds.
(def %cl-key-waiting?
  (fn (_ reader ms)
    (if (reader (lit ask)) #t (not (null? (Sys poll (list (pair 0 (list (lit in)))) ms))))))

; Exploring, the game walks a step a frame until the walk ends or a
; key arrives, which only stops it.
(def %cl-explore!
  (fn (_ g screen reader)
    (if (%cl-key-waiting? reader 30)
      (do (Term key reader) (game-exploring! g ()))
      (do (game-explore! g) (Heap collect)))))

(def %cl-loop
  (fn (self g screen reader)
    (%cl-show! g screen)
    (if (game-exploring? g) (do (%cl-explore! g screen reader) (self g screen reader))
      ((fn (_ key)
         (match
           ((null? key) ())
           ((not (null? (game-over g))) ())
           ((eq? key (lit clear)) (do (Screen repaint screen) (self g screen reader)))
           (#t (do (game-key! g key) (Heap collect) (self g screen reader)))))
       (Term key reader)))))

(def %cl-esc (fn (_ text) (Str8 append "\x1b" text)))

; The game over: the epitaph said, a score kept, a save removed.
(def %cl-finish!
  (fn (_ g set)
    (def how (game-over g))
    (match
      ((eq? how (lit saved)) (do (save-write! g (save-path "save")) (%cl-say 1 "Saved.  Play again to take it up.\n") 0))
      (#t (do (when (File exists? (save-path "save")) (File unlink (save-path "save")))
              (save-score! (save-path "scores") (game-score g) (game-deepest g)
                (match ((eq? how (lit won)) "won") ((eq? how (lit quit)) "quit") (#t (game-epitaph g))))
              (%cl-say 1 (Str8 append
                           (match ((eq? how (lit won)) "You won") ((eq? how (lit quit)) "You quit")
                                  (#t (Str8 append "You were " (game-epitaph g))))
                           " on level " (Str8 str (game-depth g)) " with " (Str8 str (player-gold (game-player g)))
                           " gold.  Score " (Str8 str (game-score g)) ".\n"))
              0)))))

(def %cl-seed
  (fn (_ opts)
    (if (null? (Opts value opts "-S")) (+ 1 (rest (Sys time-of-day))) (%cl-to-int (Opts value opts "-S")))))

(def %cl-play
  (fn (_ opts)
    ; x.sh parks the user's terminal on fd 3 while the boot stream holds
    ; fd 0; it is taken back, as the REPL and x-browse take it.
    (guard (e ()) (when (Sys isatty 3) (do (Sys dup2 3 0) (Sys close 3))))
    (def size (Term window 0))
    (match
      ((not (if (Term tty? 0) (Sys isatty 1) #f)) (do (%cl-say 2 "x-roguelike: not a terminal\n") 1))
      ((if (< (first size) 60) #t (< (rest size) 20)) (do (%cl-say 2 "x-roguelike: the terminal must be 60 by 20 at least\n") 1))
      (#t (do
        (def dir (%cl-data-dir opts))
        (def name (Opts value opts "-s" "classic"))
        (def set (data-load (Str8 append dir "/" name)))
        (def saved (save-read (save-path "save") set (rest size) (first size)))
        (def g (if (null? saved) (game-make set (%cl-seed opts) (rest size) (first size)) saved))
        (def screen (Screen make (rest size) (first size)))
        (def token (Term raw! 0))
        (Term emit 1 (Str8 append (%cl-esc "[?1049h")))
        (def failed (guard (e e) (do (%cl-loop g screen (%cl-reader)) ())))
        (Term emit 1 (Str8 append (%cl-esc "[0m") (%cl-esc "[?25h") (%cl-esc "[?1049l")))
        (Term restore! 0 token)
        (if (null? failed) (%cl-finish! g set)
          (do (%cl-say 2 (Str8 append "x-roguelike: " (%cl-err-text failed) "\n")) 1)))))))

(def %cl-scores
  (fn (_)
    (def rows (save-scores (save-path "scores")))
    (if (null? rows) (%cl-say 1 "No games yet.\n")
      (List for-each (fn (_ row) (%cl-say 1 (Str8 append row "\n"))) rows))
    0))

; ARGS, the command line after the launcher's options: the exit status.
(def roguelike-main
  (fn (_ args)
    (def opts (Opts parse roguelike-options args))
    (def words (Opts operands opts))
    (def seed (Opts value opts "-S"))
    (match
      ((not (null? (Opts unknown opts)))
        (do (%cl-say 2 (Str8 append "x-roguelike: no such option: " (Opts unknown opts) "\n" (Opts usage roguelike-options))) 2))
      ((Opts on? opts "-h") (do (%cl-say 1 (Opts usage roguelike-options)) 0))
      ((Opts on? opts "-V") (do (%cl-say 1 (Str8 append "x-roguelike " roguelike-version "\n")) 0))
      ((if (null? seed) #f (null? (%cl-to-int seed))) (do (%cl-say 2 "x-roguelike: --seed takes a number\n") 2))
      ((null? words) (guard (e (do (%cl-say 2 (Str8 append "x-roguelike: " (%cl-err-text e) "\n")) 1)) (%cl-play opts)))
      ((str=? (first words) "play") (guard (e (do (%cl-say 2 (Str8 append "x-roguelike: " (%cl-err-text e) "\n")) 1)) (%cl-play opts)))
      ((str=? (first words) "scores") (%cl-scores))
      (#t (do (%cl-say 2 (Str8 append "x-roguelike: no such command: " (first words) "\n" (Opts usage roguelike-options))) 2)))))

(provide roguelike/cli roguelike-main roguelike-options roguelike-version)
