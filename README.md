# Introduction

Supercron is a scheduler (similar to
[cron](https://man7.org/linux/man-pages/man8/cron.8.html)) that runs arbitrary
commands at specified moments of time.
The features that distiguish this implementation from many others are the following.
- Supercron never runs the command again unless the previous run of the same
  command has finished.
- When Supercron starts it runs all the commands that should have been run since
  the last time the daemon was alive. This feature is useful for desktop computers
  that are powered off periodically.
- Supercron uses intervals with a period to specify the time points at which the command
  is run. Each interval has start and end timestamp and a period. If the start
  or the end of the interval is omitted, then the interval is open (infinite). The command
  runs at `start+period`, `start+2*period` etc. until the `end` of the interval. You
  can specify any number of intervals for each command.
- Supercron like [mcron](https://www.gnu.org/software/mcron/) uses
  [Guile](https://www.gnu.org/software/guile/) as a configuration language.
- Supercron uses a list of arguments to specify the command to be run and does
  not use shell by default. This is in contrast to using single string which
  inevitably leads to problems with whitespace.

# Usage

Here is an example of the configuration file called `example.scm`:
```scheme
(list
  (make <task>
    #:name "sleep"
    #:schedule (list (make <interval>
                       #:start (time "2021-01-01T00:03:00+0300")
                       #:period (period "1s")))
    #:arguments '("/bin/sleep" "10s")))
```
In this file we specify single task called "sleep" that runs "/bin/sleep" binary
with argument "10s". This command is launched periodically every second starting
from "2021-01-01T00:03:00+0300" up to infinity. To run Supercron we write
`supercron --verbose --period 2s example.scm`. In "verbose" mode Supercron
prints a message every time the command runs or finishes, and "period"
option sets global period to 2 seconds. We get the following output:
```
2021-06-06T20:36:10+0300 Launched process 1306: (/bin/sleep 10s)
2021-06-06T20:36:12+0300 Not launching task sleep, it is already active.
2021-06-06T20:36:14+0300 Not launching task sleep, it is already active.
2021-06-06T20:36:16+0300 Not launching task sleep, it is already active.
2021-06-06T20:36:18+0300 Not launching task sleep, it is already active.
2021-06-06T20:36:20+0300 Terminated process 1306: exit code 0
2021-06-06T20:36:20+0300 Launched process 1322: (/bin/sleep 10s)
2021-06-06T20:36:22+0300 Not launching task sleep, it is already active.
2021-06-06T20:36:24+0300 Not launching task sleep, it is already active.
...
```
In order to view full schedule for the next 24 hours we use
`supercron --schedule --limit 5 example.scm`:
```
Schedule from 2021-06-06T20:39:19+0300 to 2021-06-07T20:39:19+0300 (showing at most 5 entries):
2021-06-06T20:39:19+0300 sleep
2021-06-06T20:39:20+0300 sleep
2021-06-06T20:39:21+0300 sleep
2021-06-06T20:39:22+0300 sleep
2021-06-06T20:39:23+0300 sleep
```
The full list of options is given by `supercron --help`.

# Installation

Install `supercron.scm` to the standard location for your system
and create a wrapper script similar to the following.
```scheme
#!/bin/guile3.0 --no-auto-compile
!#
(load "/usr/share/guile/site/3.0/supercron.scm")
```
