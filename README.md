# Just Task It — Offline-First Sync Queue

A Flutter task management app with full offline-first support: local caching, offline writes, durable sync queue, idempotent retries, and conflict resolution backed by Supabase.

---

## Run Instructions

### Prerequisites
- Flutter SDK >= 3.0.0
- Android emulator or physical device
- Internet connection for first launch (to authenticate)

### Steps
1. git clone <your-repo-url>
2. cd just_task_it
3. flutter pub get
4. flutter run

### Dependencies Added
- hive_flutter: ^1.1.0       (local storage for tasks + sync queue)
- connectivity_plus: ^6.0.5  (network state detection)
- uuid: ^4.5.1               (client-side UUID generation)

---

## Approach

### Architecture
The app uses GetX for state management with a clean layered structure:

- DashboardController: UI state, loads from Hive cache first before any network call
- TaskService: decides local vs remote write based on connectivity
- SyncQueueService: manages queued actions, retries, idempotency, and observability logs
- HiveService: abstraction over two Hive boxes (tasks box + sync queue box)
- ConnectivityService: monitors network state, triggers sync on reconnect

### Data Flow

User Action
    |
    v
Write to Hive (instant) --> Update UI immediately
    |
    |-- Online? --> Call Supabase --> mark isSynced = true in Hive
    |
    +-- Offline? --> Add to Sync Queue (persisted in Hive)
                          |
                    App comes back online
                          |
                    Process Queue --> Supabase (upsert)
                                         |
                                      Fails? --> retry with backoff (max 2x)

### Local Storage
Two Hive boxes:
- tasks_box: full task cache keyed by task ID, loaded instantly on app open
- sync_queue_box: pending actions keyed by idempotency key, survives app restarts

No code generation required. All data stored as plain Maps for simplicity.

### Idempotency
Every queued action gets a deterministic idempotency key:

  {userId}_{actionType}_{taskId}

Example: b96fb282_toggle_a998fc1b

The same action always produces the same key. Supabase upserts are used instead
of inserts — safe to call multiple times with zero duplicates. For toggle and edit
actions, the queued item is always overwritten with the latest state so only the
final value syncs.

### Conflict Resolution: Last-Write-Wins
Every task carries an updatedAt timestamp set at the exact time of the user action.
On sync, Supabase receives an upsert with the local timestamp. Whichever write has
the most recent timestamp is the one that persists.

Why last-write-wins: This is a single-user task app. There is no collaborative
editing scenario, so the simplest strategy that prevents data loss is the correct
one. A merge strategy would add significant complexity with no real benefit here.

### Retry with Backoff
- Maximum 2 retries per action
- Delay: 2 seconds on first retry, 4 seconds on second retry
- After max retries, action stays in queue for the next sync cycle
- Queue is fully persisted in Hive and survives app kills and restarts

---

## Tradeoffs

Plain Maps in Hive (no generated adapters)
  -> Faster to implement, slightly less type-safe than generated adapters

Client-generated UUIDs
  -> Enables true offline-first adds; requires upsert instead of insert on Supabase

Polling for connectivity UI every 3s
  -> Simple but not instant; ConnectivityService stream handles actual sync triggering

Last-write-wins conflict strategy
  -> Simple and correct for single-user; would be wrong for collaborative apps

Kept GetX architecture
  -> No migration cost from existing app; works cleanly with reactive observables

Supabase instead of Firebase
  -> Same concept as mock API; Supabase upsert works identically for this use case

---

## Limitations

- No per-field merge: if two devices edit different fields of the same task offline,
  only the last sync wins entirely
- No auth-aware queue: if the user logs out while items are queued, those actions
  will fail on next login
- No TTL on cache: stale cached data is never expired
- Connectivity polling: UI sync badge updates every 3 seconds instead of instantly
- Single user only: conflict strategy not designed for multi-device scenarios

---

## Next Steps

- Add TTL to tasks_box: expire cache after 24 hours and force a fresh fetch
- Add unit tests for idempotency key generation and queue deduplication
- Handle auth expiry: pause queue processing if session expired, re-authenticate first
- Add visible sync status banner showing pending queue count in real time
- Replace 3-second polling with a fully reactive GetX stream
- Support partial field-level conflict resolution for richer merge strategies

---

## Verification Evidence

All screenshots are in the /verification folder.

### Test 1 — Offline Add Task
- Turned on Airplane mode
- Added a new task
- Task appeared instantly in UI loaded from Hive cache
- Logs confirmed: Offline — task saved locally and queued | Queue size: 1
- Turned Airplane mode off
- Logs confirmed: Synced action: add | Queue size: 0
- Screenshot: verification/test1_offline_add.png

### Test 2 — Offline Toggle Task
- Turned on Airplane mode
- Toggled a task complete
- UI updated instantly via optimistic update
- Logs confirmed: Offline — toggle queued | Queue size: 1
- Turned Airplane mode off
- Logs confirmed: Synced action: toggle | Queue size: 0
- Screenshot: verification/test2_offline_toggle.png

### Test 3 — Retry + Idempotency
- Added simulateFailOnce flag to force first sync attempt to throw an exception
- Turned on Airplane mode, toggled a task, turned off Airplane mode
- Logs confirmed full retry flow:
    Failed action: toggle | error: Simulated transient failure for demo
    Retrying in 2s... (attempt 1/2)
    Attempting action: toggle | retry: 1
    Synced action: toggle | Queue size: 0
- Verified in Supabase table: only 1 row updated, not 2 (idempotency proven)
- Screenshot: verification/test3_retry_idempotency.png

### Test 4 — Queue Survives App Restart
- Turned on Airplane mode
- Added a task, confirmed Queue size: 1 in logs
- Fully killed the app from recents
- Reopened the app while still on Airplane mode
- Task still visible in UI loaded from Hive
- Turned Airplane mode off
- Logs confirmed queue processed on startup:
    App started online. Processing any leftover queue...
    Synced action: add
    Queue size: 0
- Screenshot: verification/test4_restart_durability.png

---

## AI Prompt Log

### Prompt 1
Prompt:
I have a Flutter task management app with GetX and Supabase. I need to add
offline-first support with a sync queue, retries, and idempotency. What files
do I need to create and modify?

Key response summary:
Suggested creating HiveService, SyncQueueService, ConnectivityService and
modifying TaskModel, TaskService, DashboardController, and main.dart.
Recommended Hive for persistence and connectivity_plus for network detection.

Decision: Accepted with modification

Why:
Accepted the overall architecture. Rejected Hive generated type adapters via
build_runner and used plain Maps instead to eliminate code generation overhead.

---

### Prompt 2
Prompt:
Write the SyncQueueService with idempotency key generation, enqueue methods
for add, toggle, edit and delete, processQueue with retry and backoff, and
observability logs.

Key response summary:
Generated full service with deterministic key userId_actionType_taskId, upsert
based sync, max 2 retries at 2s and 4s delays, console logs for every queue
state change.

Decision: Accepted

Why:
Idempotency key format was deterministic and collision-safe. Upsert over insert
was correct for replay safety. Retry logic was minimal and clearly explainable.

---

### Prompt 3
Prompt:
Modify DashboardController to load from Hive cache first then refresh from
Supabase in background. Remove the tempTask pattern since TaskService now
returns a real UUID task directly.

Key response summary:
Replaced tempTask pattern with direct service return, added _loadFromCache as
first call in onInit, added pendingQueueCount as reactive observable, added
connectivity polling every 3 seconds.

Decision: Accepted with modification

Why:
Accepted cache-first loading and queue count observable. Changed polling
interval from 5s to 3s for more responsive feedback during demo.

---

### Prompt 4
Prompt:
Write ConnectivityService to check connectivity on app start, process leftover
queue on startup if online, and trigger processQueue whenever device comes back
online.

Key response summary:
Used connectivity_plus stream listener, checked initial state on init, called
processQueue on both startup when online and on every offline to online
transition during session.

Decision: Accepted

Why:
Covered both app restart while online and comes back online mid session
scenarios. Both required by the assignment rubric. No changes needed.
