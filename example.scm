(list
  (make <task>
    #:name "sleep"
    #:schedule (list (make <interval>
                       #:start (time "2021-01-01T00:03:00+0300")
                       #:period (period "1s")))
    #:arguments '("/home/igankevich/.guix-profile/bin/sleep" "10s")))
