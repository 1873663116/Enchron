------------------------- MODULE PlaybackLanes -------------------------
\* The subscription protocol of the shared demux source.
\*
\* The C source is Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/
\* PlaybackFFmpegBridge.c. Each action is named after the code that does it.
\*
\*   Read      PBFFmpegDemuxSourceReadLoop         enqueues a packet
\*   Attach    PBFFmpegDemuxSourceTakeOverStream   a lane takes a stream
\*   Release   PBFFmpegDemuxSourceReleaseStream    token-guarded release
\*   Seek      PBFFmpegDemuxSourceSeek             clears the queues
\*   Advance   the playhead moving forward
\*   Dequeue   a lane showing the oldest packet it holds
\*
\* The one design question: when a lane takes a stream, are the packets that
\* the stream buffered before the playhead reached its current position
\* dropped, or shown?
\*
\* Out of scope: history replay, packet deduplication across a re-attach, and
\* every timing bound. The Swift tests named in the project skill that runs
\* this model cover those.

EXTENDS Naturals, FiniteSets

CONSTANTS Lanes, Streams, Packets, Positions, Prebuffer, TrimOnAttach

VARIABLES queue, history, subscribers, owner, position, attachPosition,
          deliveredSinceAttach

vars == <<queue, history, subscribers, owner, position, attachPosition,
          deliveredSinceAttach>>

None == "none"

MinOf(set) == CHOOSE m \in set : \A x \in set : m <= x

EmptyQueues == [s \in Streams |-> {}]
NoOwners == [s \in Streams |-> None]
NoSubscribers == [s \in Streams |-> 0]
NoAttach == [l \in Lanes |-> 0]
NoDeliveries == [l \in Lanes |-> {}]

Init ==
  /\ queue = EmptyQueues
  /\ history = EmptyQueues
  /\ subscribers = NoSubscribers
  /\ owner = NoOwners
  /\ position = 0
  /\ attachPosition = NoAttach
  /\ deliveredSinceAttach = NoDeliveries

\* The read loop enqueues a packet when the stream has a subscriber or when
\* the source prebuffers it, and never below the playhead.
Read(s, p) ==
  /\ p \in Packets
  /\ p \notin history[s]
  /\ p >= position
  /\ (subscribers[s] > 0 \/ s \in Prebuffer)
  /\ queue' = [queue EXCEPT ![s] = queue[s] \cup {p}]
  /\ history' = [history EXCEPT ![s] = history[s] \cup {p}]
  /\ UNCHANGED <<subscribers, owner, position, attachPosition,
                 deliveredSinceAttach>>

\* Taking a stream. TrimOnAttach decides whether the packets buffered below
\* the playhead survive the take-over.
Attach(l, s) ==
  /\ subscribers[s] = 0
  /\ (\A other \in Streams : owner[other] # l)
  /\ owner' = [owner EXCEPT ![s] = l]
  /\ subscribers' = [subscribers EXCEPT ![s] = 1]
  /\ queue' = [queue EXCEPT ![s] =
       IF TrimOnAttach
       THEN {p \in queue[s] : p >= position}
       ELSE queue[s]]
  /\ attachPosition' = [attachPosition EXCEPT ![l] = position]
  /\ deliveredSinceAttach' = [deliveredSinceAttach EXCEPT ![l] = {}]
  /\ UNCHANGED <<history, position>>

Release(l, s) ==
  /\ owner[s] = l
  /\ subscribers' = [subscribers EXCEPT ![s] = 0]
  /\ owner' = [owner EXCEPT ![s] = None]
  /\ UNCHANGED <<queue, history, position, attachPosition,
                 deliveredSinceAttach>>

\* A seek moves the playhead and re-anchors every lane at the target.
Seek(q) ==
  /\ q \in Positions
  /\ position' = q
  /\ queue' = EmptyQueues
  /\ history' = EmptyQueues
  /\ attachPosition' = [l \in Lanes |-> q]
  /\ deliveredSinceAttach' = NoDeliveries
  /\ UNCHANGED <<subscribers, owner>>

Advance ==
  /\ \E q \in Positions : q > position
  /\ position' = position + 1
  /\ UNCHANGED <<queue, history, subscribers, owner, attachPosition,
                 deliveredSinceAttach>>

Dequeue(l, s) ==
  /\ owner[s] = l
  /\ queue[s] # {}
  /\ LET p == MinOf(queue[s]) IN
       /\ queue' = [queue EXCEPT ![s] = queue[s] \ {p}]
       /\ deliveredSinceAttach' = [deliveredSinceAttach EXCEPT
            ![l] = deliveredSinceAttach[l] \cup {p}]
       /\ UNCHANGED <<history, subscribers, owner, position, attachPosition>>

Next ==
  \/ \E s \in Streams, p \in Packets : Read(s, p)
  \/ \E l \in Lanes, s \in Streams : Attach(l, s)
  \/ \E l \in Lanes, s \in Streams : Release(l, s)
  \/ \E q \in Positions : Seek(q)
  \/ Advance
  \/ \E l \in Lanes, s \in Streams : Dequeue(l, s)

Spec == Init /\ [][Next]_vars

\* A lane never shows a packet that was already old when it took the stream.
NoStaleDelivery ==
  \A l \in Lanes :
    \A p \in deliveredSinceAttach[l] : p >= attachPosition[l]

\* An owner is exactly a stream with a subscriber.
OwnerIsSubscriber ==
  \A s \in Streams : (owner[s] # None) <=> (subscribers[s] = 1)

====
