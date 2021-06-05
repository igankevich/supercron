(use-modules
  (oop goops)
  (srfi srfi-1)
  (ice-9 format)
  (ice-9 getopt-long))

(define ULONG_MAX 18446744073709551615)
(define %iso-date "%Y-%m-%dT%H:%M:%S%z")
(define %min-timestamp 0)
(define %max-timestamp ULONG_MAX)
(define %default-period 60)
(define %version "0.1.1")
(define %verbose? #f)

(define-class <task> ()
  (name #:init-keyword #:name #:accessor task-name #:init-value #f)
  (arguments #:init-keyword #:arguments #:accessor task-arguments)
  (environment #:init-keyword #:environment #:accessor task-environment #:init-value '())
  (uid #:init-keyword #:uid #:accessor task-uid #:init-value #f)
  (gid #:init-keyword #:gid #:accessor task-gid #:init-value #f)
  (schedule #:init-keyword #:schedule #:accessor task-schedule #:init-value '()))

(define-method (task-name/human (task <task>))
  (define name (task-name task))
  (if name name (string-join (task-arguments task) " ")))

(define-class <interval> ()
  (start #:init-keyword #:start #:accessor interval-start #:init-value %min-timestamp)
  (end #:init-keyword #:end #:accessor interval-end #:init-value %max-timestamp)
  (period #:init-keyword #:period #:accessor interval-period #:init-value 0))

(define-method (write (interval <interval>) port)
  (format port "[from ~a to ~a period ~a]"
          (interval-start interval)
          (interval-end interval)
          (interval-period interval)))

(define-method (interval-start-time (interval <interval>))
  (define t (interval-start interval))
  (if t t %min-timestamp))

(define-method (interval-end-time (interval <interval>))
  (define t (interval-end interval))
  (if t t %max-timestamp))

(define-method (interval-closed? (interval <interval>))
  (and (not (= (interval-start interval) %min-timestamp))
       (not (= (interval-end interval) %max-timestamp))))

(define-method (interval-count (interval <interval>))
  (define period (interval-period interval))
  (cond
    ((= period 0) 0)
    (else (truncate (/ (- (interval-end interval) (interval-start interval)) period)))))

(define-method (interval-timestamps (interval <interval>))
  (reverse
    (fold
      (lambda (x prev) (cons (+ x (car prev)) prev))
      (list (interval-start interval))
      (make-list (interval-count interval) (interval-period interval)))))

(define-method (intersect? (a <interval>) (b <interval>))
  (define a0 (interval-start-time a))
  (define a1 (interval-end-time a))
  (define b0 (interval-start-time b))
  (define b1 (interval-end-time b))
  (or (<= b0 a0 b1)
      (<= b0 a1 b1)
      (<= a0 b0 a1)
      (<= a0 b1 a1)))

(define-method (intersection (a <interval>) (b <interval>))
  (define a0 (interval-start-time a))
  (define a1 (interval-end-time a))
  (define b0 (interval-start-time b))
  (define b1 (interval-end-time b))
  (define c-1 (min a0 b0))
  (define c0 (max a0 b0))
  (define c1 (min a1 b1))
  (define period (interval-period a))
  (define n (ceiling (/ (- c0 c-1) period)))
  ;; new start timestamp is aligned with the period
  (make <interval>
    #:start (+ c-1 (* n period))
    #:end c1
    #:period period))

;; generate timestamps in the intersection of the intervals
(define-method (interval-intersection-timestamps (a <interval>) (b <interval>))
  (cond
    ((intersect? a b)
     (let ((c (intersection a b)))
       (if (interval-closed? c)
         (interval-timestamps c)
         '())))
    (else '())))

;; generate timestamps in the interval
(define-method (task-timestamps (task <task>) (interval <interval>))
  (sort!
    (append-map
      (lambda (interval-b)
        (interval-intersection-timestamps interval-b interval))
      (task-schedule task))
    (lambda (a b) (< a b))))

(define-method (task-launch (task <task>))
  (define id (primitive-fork))
  (cond
    ((= id 0)
     (let ((argv (task-arguments task)))
       (catch #t
         (lambda ()
           (if (task-gid task) (setgid (task-gid task)))
           (if (task-uid task) (setuid (task-uid task)))
           (apply execle `(,(car argv) ,(task-environment task) ,@argv)))
         (lambda (key . parameters)
           (message "Failed to execute ~a: ~a\n" argv (cons key parameters))
           (exit EXIT_FAILURE)))))
    (else
      ;; store in the database
      (if %verbose?
        (message "Launched process ~a: ~a\n" id (task-arguments task))))
    ))

(define (status->string status)
  (define (field key value)
    (if value
      (list (format #f "~a ~a" key value))
      '()))
  (string-join
    (append
      (field "exit code" (status:exit-val status))
      (field "termination signal" (status:term-sig status))
      (field "stop signal" (status:stop-sig status)))
    ", "))

(define (check-child-processes)
  (define result
    (catch #t
      (lambda ()
        (waitpid WAIT_ANY WNOHANG))
      (lambda (key . parameters)
        ;; waitpid throws ENOENT even when WNOHANG is specified
        ;;(message "waitpid: ~a\n" (cons key parameters))
        (cons 0 0))))
  (define id (car result))
  (define status (cdr result))
  (if (not (= id 0))
    (begin
      (if %verbose?
        (message "Terminated process ~a: ~a\n" id (status->string status)))
      (check-child-processes))))

(define (launch-new-tasks tasks old-timestamp current-timestamp)
  (define interval
    (make <interval>
      #:start old-timestamp
      #:end current-timestamp))
  (define current-tasks
    (filter
      (lambda (task) (not (null? (task-timestamps task interval))))
      tasks))
  (for-each task-launch current-tasks))

(define (agenda tasks interval max-count)
  (define entries
    (sort!
      (append-map
        (lambda (task)
          (map
            (lambda (timestamp) (cons timestamp task))
            (task-timestamps task interval)))
        tasks)
      (lambda (a b) (< (car a) (car b)))))
  (take
    entries
    (min max-count (length entries))))

(define (timestamp->string t)
  (strftime %iso-date (localtime t)))

(define (string->timestamp str)
  (let ((tm (car (strptime %iso-date str))))
    (set-tm:zone tm (tm:zone (localtime (current-time))))
    (car (mktime tm))))

(define (message format-string . rest)
  (define msg
    (apply format
           `(#f
             ,(string-append "~a " format-string)
             ,(strftime %iso-date (localtime (current-time)))
             ,@rest)))
  (display msg (current-error-port))
  (force-output (current-error-port)))

(define (period str)
  (define s (string-trim-both str))
  (define n (string-length s))
  (define (parse suffix-size multiplier)
    (* multiplier (string->number (substring s 0 (- n suffix-size)))))
  (max 1
       (cond
         ((string-suffix? "s" s) (parse 1 1))
         ((string-suffix? "m" s) (parse 1 60))
         ((string-suffix? "h" s) (parse 1 (* 60 60)))
         ((string-suffix? "d" s) (parse 1 (* 60 60 24)))
         ((string-suffix? "M" s) (parse 1 (* 60 60 24 31)))
         ((string-suffix? "y" s) (parse 1 (* 60 60 24 31 12)))
         (else (let ((result (string->number s)))
                 (if result result 0))))))

(define seconds 1)
(define minutes 60)
(define hours (* 60 60))
(define days (* 60 60 24))
(define months (* 60 60 24 31))
(define years (* 60 60 24 31 12))
(define time string->timestamp)

(define (load-tasks filename)
  (load filename))

(define (usage)
  (define name (car (command-line)))
  (format #t "usage: ~a [--period duration] [--verbose] filename...\n" name)
  (format #t "usage: ~a [--schedule] [--from timestamp] [--to timestamp] [--limit max-entries] filename...\n" name))

(if (= (length (command-line)) 1)
  (begin
    (usage)
    (exit EXIT_FAILURE)))

(define options
  (getopt-long (command-line)
               `((schedule (required? #f) (value #f))
                 (from (required? #f) (value #t))
                 (to (required? #f) (value #t))
                 (limit (required? #f) (value #t))
                 (period (required? #f) (value #t))
                 (verbose (single-char #\v) (required? #f) (value #f))
                 (help (single-char #\h) (required? #f))
                 (version (required? #f)))))

(define files (option-ref options '() '()))

(if (option-ref options 'help #f)
  (begin
    (usage)
    (exit EXIT_SUCCESS)))

(if (option-ref options 'version #f)
  (begin
    (format #t "~a" %version)
    (exit EXIT_SUCCESS)))

(define tasks
  (append-map
    (lambda (filename) (load-tasks filename))
    files))

(if (option-ref options 'schedule #f)
  (let ((from-str (option-ref options 'from #f))
        (to-str (option-ref options 'to #f))
        (limit-str (option-ref options 'limit #f)))
    (define from (if from-str (string->timestamp from-str) (current-time)))
    (define to (if to-str (string->timestamp to-str) (+ from (* 60 60 24))))
    (define limit (if limit-str (string->number limit-str) 1000))
    (format #t "Schedule from ~a to ~a (showing at most ~a entries):\n"
            (timestamp->string from) (timestamp->string to) limit)
    (for-each
      (lambda (pair)
        (define timestamp (car pair))
        (define task (cdr pair))
        (format #t "~a ~a\n" (timestamp->string timestamp) (task-name/human task)))
      (agenda tasks (make <interval> #:start from #:end to) limit))
    (exit EXIT_SUCCESS)))

(set! %verbose? (option-ref options 'verbose #f))
(define %period
  (let ((period-str (option-ref options 'period #f)))
    (if period-str (period period-str) %default-period)))
(define old-timestamp (current-time))
(define current-timestamp old-timestamp)
(while #t
  (sleep %period)
  ;; intervals are all closed, so we add 1 second here
  ;; to not repeat the same task twice
  (set! old-timestamp (+ 1 current-timestamp))
  (set! current-timestamp (current-time))
  (launch-new-tasks tasks old-timestamp current-timestamp)
  (check-child-processes))
