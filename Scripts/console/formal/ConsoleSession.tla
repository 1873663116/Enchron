---- MODULE ConsoleSession ----
\* Model of Scripts/console/daemon.py and Scripts/console/transport.py.
\* One worktree, one target device. Two operators may act at the same time.
\*
\* The actions below mirror the code:
\*   Ping / Spawn        ensure_running
\*   EnsureReuse         Channel.ensure_session, first branch
\*   EnsureAdopt         Channel.ensure_session, second branch
\*   EnsureLaunch        Channel.ensure_session, third branch (halt then launch)
\*   Publish             the runner writing ready.json
\*   RunnerDies          xcodebuild exiting
\*   ForeignRunner       a runner this daemon did not start
\*   IdleExit            Server.serve, the idle window closing
\*   Invoke              Channel.invoke

EXTENDS Naturals, TLC

CONSTANTS Operators, SessionId, ForeignId

VARIABLES
  daemons,     \* `daemon --serve` processes alive
  runners,     \* xcodebuild test-without-building processes alive
  readyId,     \* sessionID stored in ready.json; 0 means the file is absent
  held,        \* sessionID this daemon treats as held; 0 means none
  liveSession, \* sessionID the live runner really serves; 0 means none
  owned,       \* TRUE while the live runner is the one this daemon started
  observed,    \* daemons each operator saw at its last ping
  pc           \* operator program counter

vars == <<daemons, runners, readyId, held, liveSession, owned, observed, pc>>

Init ==
  /\ daemons = 0
  /\ runners = 0
  /\ readyId = 0
  /\ held = 0
  /\ liveSession = 0
  /\ owned = FALSE
  /\ observed = [o \in Operators |-> 0]
  /\ pc = [o \in Operators |-> "start"]

Ping(o) ==
  /\ pc[o] = "start"
  /\ observed' = [observed EXCEPT ![o] = daemons]
  /\ pc' = [pc EXCEPT ![o] = "spawn"]
  /\ UNCHANGED <<daemons, runners, readyId, held, liveSession, owned>>

\* A spawned server pings before it binds and exits when one already answers.
Spawn(o) ==
  /\ pc[o] = "spawn"
  /\ observed[o] = 0
  /\ daemons' = IF daemons = 0 THEN 1 ELSE daemons
  /\ pc' = [pc EXCEPT ![o] = "ensure"]
  /\ UNCHANGED <<runners, readyId, held, liveSession, owned, observed>>

\* Channel.alive requires the live runner to be one this daemon started.
Alive ==
  runners > 0 /\ held /= 0 /\ readyId = held /\ owned

EnsureReuse(o) ==
  /\ pc[o] = "ensure"
  /\ Alive
  /\ pc' = [pc EXCEPT ![o] = "done"]
  /\ UNCHANGED <<daemons, runners, readyId, held, liveSession, owned, observed>>

\* Adoption reads .console/session.json, so it only accepts the runner this
\* daemon recorded. A runner it never started is not adoptable.
EnsureAdopt(o) ==
  /\ pc[o] = "ensure"
  /\ ~Alive
  /\ runners > 0
  /\ readyId /= 0
  /\ owned
  /\ held' = readyId
  /\ pc' = [pc EXCEPT ![o] = "done"]
  /\ UNCHANGED <<daemons, runners, readyId, liveSession, owned, observed>>

EnsureLaunch(o) ==
  /\ pc[o] = "ensure"
  /\ ~Alive
  /\ runners' = 1
  /\ readyId' = 0
  /\ held' = 0
  /\ liveSession' = SessionId
  /\ owned' = TRUE
  /\ pc' = [pc EXCEPT ![o] = "ensure"]
  /\ UNCHANGED <<daemons, observed>>

Publish ==
  /\ runners > 0
  /\ readyId = 0
  /\ readyId' = liveSession
  /\ UNCHANGED <<daemons, runners, held, liveSession, owned, observed, pc>>

\* Dying does not remove ready.json: the file lives in the app container.
RunnerDies ==
  /\ runners > 0
  /\ runners' = runners - 1
  /\ liveSession' = 0
  /\ owned' = FALSE
  /\ UNCHANGED <<daemons, readyId, held, observed, pc>>

\* A runner this daemon did not start, so the daemon does not own it.
ForeignRunner ==
  /\ runners = 0
  /\ runners' = 1
  /\ liveSession' = ForeignId
  /\ owned' = FALSE
  /\ UNCHANGED <<daemons, readyId, held, observed, pc>>

\* A crash leaves the socket behind and halts nothing, so the record survives.
DaemonCrash ==
  /\ daemons > 0
  /\ daemons' = 0
  /\ UNCHANGED <<runners, readyId, held, liveSession, owned, observed, pc>>

IdleExit ==
  /\ daemons > 0
  /\ daemons' = daemons - 1
  /\ runners' = 0
  /\ readyId' = 0
  /\ held' = 0
  /\ liveSession' = 0
  /\ owned' = FALSE
  /\ UNCHANGED <<observed, pc>>

Invoke(o) ==
  /\ pc[o] = "done"
  /\ UNCHANGED vars

Finish(o) ==
  /\ pc[o] = "done"
  /\ UNCHANGED vars

Next ==
  \/ \E o \in Operators :
       Ping(o) \/ Spawn(o) \/ EnsureReuse(o) \/ EnsureAdopt(o)
       \/ EnsureLaunch(o) \/ Invoke(o) \/ Finish(o)
  \/ Publish
  \/ RunnerDies
  \/ ForeignRunner
  \/ DaemonCrash
  \/ IdleExit

Spec == Init /\ [][Next]_vars

\* Promise one: one runner drives the device at a time.
AtMostOneRunner == runners <= 1

\* Promise two: one daemon owns the socket.
AtMostOneDaemon == daemons <= 1

\* Promise three: a held session is the session the live runner serves.
\* A stale ready.json plus a foreign runner broke this before the daemon
\* started recording which runner it started.
AliveImpliesLive ==
  Alive => held = liveSession

====
