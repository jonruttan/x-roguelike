; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/cli.x -- the command line, and the terminal
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
; lint-known: %lang-root
;
;   x -l roguelike -- play [-set NAME] [-seed N] [-data DIR]   a game
;   x -l roguelike -- scores                                   the best games
;
; The set is a directory of .xon files under the bundle's data/, or any
; directory given to -data.  Playing takes the terminal: raw, on the
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
(import roguelike/data data-load data-get)
(import roguelike/state game-over game-epitaph game-depth game-deepest game-messages game-ask game-player player-gold)
(import roguelike/game game-make game-key! game-score game-help)
(import roguelike/draw game-draw!)
(import roguelike/save save-write! save-read save-path save-score! save-scores)

(def roguelike-version "0.1.0")

(def %cl-usage
  (Str8 join "\n"
    (list "usage: x -l roguelike -- play [-set NAME] [-seed N] [-data DIR]"
          "       x -l roguelike -- scores"
          ""
          "A set is a directory of .xon files: classic is the one shipped."
          "Playing, ? shows the keys."
          "")))

(def %cl-say (fn (_ fd text) (Sys fd-write fd text)))
(def %cl-to-int
  (fn (_ s) (guard (e ()) ((prim-ref (lit convert) (lit to)) s (Type named INTEGER) 10))))

; The options in ARGS, as an alist: (set . NAME), (seed . N), (data . DIR),
; (help . #t), (version . #t), (words . LIST), or (error . TEXT).
(def %cl-flag?
  (fn (_ a names) (List any? (fn (_ n) (str=? a n)) names)))
(def %cl-options
  (fn (self args opts words)
    (match
      ((null? args) (pair (pair (lit words) (List reverse words)) opts))
      ((%cl-flag? (first args) (list "-h" "-help" "--help")) (self (rest args) (pair (pair (lit help) #t) opts) words))
      ((%cl-flag? (first args) (list "-version" "--version")) (self (rest args) (pair (pair (lit version) #t) opts) words))
      ((%cl-flag? (first args) (list "-set" "-seed" "-data"))
        (if (null? (rest args)) (list (pair (lit error) (Str8 append (first args) " takes a value")))
          (self (List drop 2 args) (pair (pair (Str8 ->sym (Str8 sub 1 (- (Str8 length (first args)) 1) (first args))) (List ref 1 args)) opts) words)))
      ((if (Str8 starts? "-" (first args)) (< 1 (Str8 length (first args))) #f)
        (list (pair (lit error) (Str8 append "no such option: " (first args)))))
      (#t (self (rest args) opts (pair (first args) words))))))
(def %cl-opt (fn (_ opts k) ((fn (_ p) (if (null? p) () (rest p))) (Assoc find k opts))))

; Where the sets are: -data, X_ROGUELIKE_DATA, the installed bundle's
; data/, or data/ here.
(def %cl-data-dir
  (fn (_ opts)
    (def env (Sys getenv "X_ROGUELIKE_DATA"))
    (def root (guard (e ()) %lang-root))
    (match ((not (null? (%cl-opt opts (lit data)))) (%cl-opt opts (lit data)))
           ((if (null? env) #f (not (str=? env ""))) env)
           ((str? root) (Str8 append root "/data"))
           (#t "data"))))

(def %cl-err-text
  (fn (_ e)
    (match ((Err err? e) (e msg))
           ((str? e) e)
           (#t (Err code-of e)))))

; --- the terminal ------------------------------------------------------------

(def %cl-reader
  (fn (_)
    (def box (Vector of ()))
    (fn (self . ask)
      (if (null? ask)
        (do (when (null? (Vector ref 0 box)) (Vector set! 0 (Sys fd-read 0 64) box))
            (if (null? (Vector ref 0 box)) ()
              ((fn (_ b) (Vector set! 0 (rest (Vector ref 0 box)) box) b) (first (Vector ref 0 box)))))
        (not (null? (Vector ref 0 box)))))))

(def %cl-show!
  (fn (_ g screen)
    (game-draw! g screen)
    (Term emit 1 (Screen render screen))))

(def %cl-loop
  (fn (self g screen reader)
    (%cl-show! g screen)
    (def key (Term key reader))
    (match
      ((null? key) ())
      ((not (null? (game-over g))) ())
      ((eq? key (lit clear)) (do (Screen repaint screen) (self g screen reader)))
      (#t (do (game-key! g key) (Heap collect) (self g screen reader))))))

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

(def %cl-seed (fn (_ opts) (if (null? (%cl-opt opts (lit seed))) (+ 1 (rest (Sys time-of-day))) (%cl-to-int (%cl-opt opts (lit seed))))))

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
        (def name (if (null? (%cl-opt opts (lit set))) "classic" (%cl-opt opts (lit set))))
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
    (def opts (%cl-options args () ()))
    (def words (%cl-opt opts (lit words)))
    (match
      ((not (null? (%cl-opt opts (lit error))))
        (do (%cl-say 2 (Str8 append "x-roguelike: " (%cl-opt opts (lit error)) "\n" %cl-usage)) 2))
      ((%cl-opt opts (lit help)) (do (%cl-say 1 %cl-usage) 0))
      ((%cl-opt opts (lit version)) (do (%cl-say 1 (Str8 append "x-roguelike " roguelike-version "\n")) 0))
      ((null? words) (guard (e (do (%cl-say 2 (Str8 append "x-roguelike: " (%cl-err-text e) "\n")) 1)) (%cl-play opts)))
      ((str=? (first words) "play") (guard (e (do (%cl-say 2 (Str8 append "x-roguelike: " (%cl-err-text e) "\n")) 1)) (%cl-play opts)))
      ((str=? (first words) "scores") (%cl-scores))
      (#t (do (%cl-say 2 (Str8 append "x-roguelike: no such command: " (first words) "\n" %cl-usage)) 2)))))

(provide roguelike/cli roguelike-main roguelike-version)
