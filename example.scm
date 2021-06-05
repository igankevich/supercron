(list
  (make <task>
    #:schedule (list (make <interval>
                       #:start (time "2021-01-01T00:03:00+0300")
                       #:period (period "1s")))
    #:arguments '("/run/current-system/profile/bin/hostname")))
