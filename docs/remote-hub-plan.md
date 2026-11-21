# Plan: one hub, HerdrDesk on any Mac

Status: design, not implemented. Nothing in this document changes current behavior.

## Goal

Open HerdrDesk on a second Mac (a laptop, say) and get the same screen as on the main Mac: the same agents, conversations, questions, card board and computer settings, with the same buttons and the same safety rules. A new Mac should be able to join with a single setup step.

Not goals for the first version:
- Running leads on several Macs at once.
- Automatic failover when the main Mac is off.
- Syncing app data between Macs.

## Decision: one hub, every other Mac is a window

One Mac is the **hub**. Leads run there, and every record lives there: the card board, `machines.json`, answer and send ledgers, results, lineage, handoffs, and live-chat state. Every other Mac running HerdrDesk is a **viewer**. It draws the page and forwards what the person does to the hub. It keeps no records of its own.

Why not let every Mac keep its own records:
- **Things get done twice.** The answer ledger, `send.lock` and direct-send ledger are per Mac. Two Macs could each answer the same question once. The `ask.state=sending` label is informational, not a compare-and-set.
- **Records split.** The hub stores a terminal as `x` and a viewer sees it as `hub/x`. Lineage identities, epoch hashes, attachment session keys and handoff parties would never match.
- **Some data can only be read on the hub.** Live chat finds a terminal's transcript through the hub's process table: `~/.claude/sessions/<pid>.json` for Claude Code, and `ps` plus `lsof` on `~/.codex/sessions` for Codex. A viewer has none of these.
- **User-facing replies are matched per process.** A reply is marked user-facing by matching a receipt armed by the sending process (per-process UUID, local `user-dispatch/`) against the transcript that same process reads. The sender and the transcript reader must be the same process on the same Mac.

## Approaches considered

**A. Redirect each feature to the hub.** Read the card board, results and transcripts through `hc exec --on` / `hc file read --on`, one feature at a time. This was rejected:
- More than ten separate call sites change.
- The duplicate-answer and address-mismatch problems above still need their own fixes.
- Live chat would need a remote `ps`/`lsof` walk every few seconds.

**B. Viewer shell plus hub bridge (chosen).** The app already has two narrow seams:
- **Page to app:** one message handler, `webkit.messageHandlers.desk`.
- **App to page:** one `call(script, args)` helper for every `desk.*` callback.

In B, the controller logic runs on the hub, and only those two seams cross the network. Everything that works on the hub today keeps working unchanged, because it still runs on the hub.

## Architecture

```
viewer Mac                                   hub Mac
┌────────────────────────┐   ssh (key)   ┌─────────────────────────────────┐
│ HerdrDesk (viewer)     │ ───────────── │ HerdrDesk --bridge (on demand)  │
│  WKWebView + web UI    │  JSON lines   │  same controller as the GUI app │
│  page msg  ──────────► │ ────────────► │  hc, herdr-task, ledgers,       │
│  ◄────────── desk.*    │ ◄──────────── │  live chat, lineage, results    │
└────────────────────────┘               └─────────────────────────────────┘
```

### Hub bridge: `HerdrDesk --bridge`

- **A headless mode of the same executable,** like the existing `--lineage` mode. It builds the same controller the window uses, with a stdio sink in place of the WKWebView.
- **Started on demand by the viewer:** `ssh <hub> '<app>/Contents/MacOS/HerdrDesk' --bridge`. There is no resident service, LaunchAgent or open port. It exits when stdin closes, so closing the viewer or dropping the network stops it.
- **Same user, same data folder** as the hub's GUI app.
- **Startup handshake:** the first line is a `hello` with the bridge's app version and protocol version. On a mismatch, the viewer shows "update HerdrDesk on the hub" and stays read-only.

SSH is the transport because it gives a full-duplex byte stream with key authentication that the setup step already arranges. `hc exec` returns one result per call and is not a stream. An `hc connect`-based transport can replace SSH later without changing the protocol.

### Protocol (JSON lines, one object per line)

- **viewer → hub:** `{"t":"page","body":{…}}`. This is the exact message the page posted (`ready`, `send`, `answer`, `approval`, `machine`, `terminalWatch`, and so on). The viewer adds nothing and never builds hc commands itself.
- **hub → viewer:** `{"t":"call","fn":"update","args":{…}}`. This mirrors every `call(script, args)`: `update`, `notice`, `sendResult`, `questionResult`, `machineResult`, `terminalOutput`, and so on.
- **Flow control:** `terminalOutput` is awaited today for flow-control credit. The bridge waits for a `{"t":"ack","id":…}` from the viewer before sending more output to that watcher.
- **Size:** the full `update` snapshot is large. The bridge sends it only when it changes, and may send a field-level diff later. The first version sends the whole snapshot, with a size limit (refused and logged if exceeded).

### What stays on the viewer

| Feature | Viewer behaviour |
|---|---|
| Window-key and app-active checks for `machine`, `terminalInput`, `copyChatID`, link opening | Checked on the viewer, before forwarding. The bridge also refuses these unless the viewer marks the message as coming from a focused, active window. |
| `HERDRDESK_NO_SEND=1` | Honoured on the viewer: it forwards nothing that sends. The bridge has its own flag for a read-only hub. |
| Sounds, language, appearance | Local. |
| Attachments | The file is on the viewer. The viewer streams it to the bridge in chunks (`{"t":"file",…}`). The bridge writes it into the hub's `attachments/` and continues with the hub path, exactly as today. |
| Image thumbnails (`chatImages`) | Read on the hub by the bridge and returned as data. The current rule (only under `~/{Pictures,Downloads,Documents,workspace}`) is unchanged. |
| `herdrdesk-path:` links | A hub path cannot be opened on the viewer. The viewer offers to copy the path or fetch a copy of the file through the bridge. |
| `open` (focus the terminal in Herdr) | Uses the viewer's own Herdr app with the hub-prefixed address. If that fails, it says so. |

### Addresses

The bridge runs on the hub, so its addresses are the hub's bare addresses. Records keep matching the hub GUI app's records. The page treats the bridge's terminals as local. The bridge reports `localMachine` as the hub's machine name, so the device label is right. Today `localMachine` is never sent, which is fixed as part of this work.

### Two processes on the hub

The hub GUI app and a bridge (or two bridges, for two viewers) can run at once on the same data folder. Today's stores were written with one process in mind:

| Store | Today | Needed |
|---|---|---|
| `send.lock` (flock) | Works across processes on one Mac | Nothing: this is what makes the hub the only sender. |
| Answer ledger, direct ledger | Files written before `hc send` | Re-read under `send.lock` right before sending. Then a question answered from any window is refused everywhere else. |
| `user-dispatch/` claims | Per process UUID | Nothing: each process claims only its own receipts, because the sender and the reader are the same process. |
| `live-replies.json`, `handoffs.json`, `lineage/state.json` | Whole-file atomic writes | Add a write lock and re-read before each write (lineage already has `write.lock`). Otherwise the last writer wins. |
| `herdr-task` (`machines.json`, `state/`) | Already has its own lock (`spawn_lock`) | Nothing. |

### Hub setting and the viewer screens

- **Setting file:** `~/Library/Application Support/app.herdrdesk/hub.json`, holding `{"ssh":"user@host","app":"/Applications/HerdrDesk.app"}`. If the file is missing, this Mac is the hub and the app works exactly as today.
- **Connecting:** the viewer shows "Connecting to the hub" until the `hello` arrives.
- **Hub not reachable:** the viewer shows "Hub not connected" and the last error. It never shows an empty board as if nothing were running. It retries with a backoff of 5s, then 15s, then 60s, while the window is open. It never retries while the app is closed.

## New Mac setup: `herdrdesk-join`

A script run once on the new Mac:

1. Check that Tailscale (or another route to the hub) and Herdr are installed.
2. Create `~/.ssh/id_ed25519` if it is missing, and register its public key on the hub with `ssh-copy-id`. **The hub password is typed once here, by the person.**
3. Add the hub's public key to this Mac's `~/.ssh/authorized_keys`. The hub then uses this key to place card workers here.
4. Add each Mac to the other's Herdr machine list (`hc machine add`).
5. Write `hub.json`.
6. Install HerdrDesk (a copy of the hub's build, or a release download).
7. Add this Mac to the hub's `machines.json` with `herdr-task machine add`, which is new. The Mac starts **not ready**, with 0 slots.

After that, the rest happens in HerdrDesk on any Mac: turn the computer on, set its slots, and "receive" team repos (this already exists). AI logins (Claude, Codex) on the new Mac stay with the person.

The script prints each step and stops at the first failure. Every step can safely be run again: an existing key is reused, a registered key is not added twice, and an existing machine entry is left alone.

## Later: moving the hub

Moving the hub means moving where the leads live. It is a deliberate, manual operation, never automatic. If it were automatic, a hub that was merely asleep could end up with a second hub beside it.

1. Pause new assignments on every team. Running cards finish or stop.
2. Copy the leads' agent sessions (`~/.codex`, `~/.claude` project files), the card board and `machines.json`, app data, results, and the team repos to the new hub. Then verify the copies.
3. Start the leads on the new hub by resuming their existing sessions.
4. Point every viewer's `hub.json` at the new hub.
5. The old hub becomes an ordinary computer in `machines.json`, so it can take card workers.

During steps 1–3, neither Mac makes new assignments. This is the same rule the existing lead hand-over (authority epoch) follows. A `herdrdesk-move-hub` helper can script the copy and verify steps once the first version has been used for a while.

## Phases

1. **Bridge and viewer.**
   - `--bridge` mode with a stdio sink.
   - Viewer mode driven by `hub.json`.
   - The connection screens.
   - Locks for the shared stores.
   - Attachment streaming.
   - `localMachine`.
2. **Setup.** `herdrdesk-join` and `herdr-task machine add`.
3. **Moving the hub.** The helper and the runbook.

## Testing

- **Protocol:**
  - Round-trip every page message type and every `desk.*` call through a pipe.
  - The bridge exits on EOF.
  - A version mismatch leaves the viewer read-only.
- **Two processes:**
  - Two controllers on one data folder answer the same question. Exactly one `hc send` runs (fake `hc`).
  - Concurrent writes to `live-replies.json` and `handoffs.json` lose nothing.
- **Viewer guards:**
  - `machine` and `terminalInput` from an unfocused viewer window are refused on both sides.
  - With `NO_SEND`, nothing is forwarded that sends.
- **Hub not reachable:** the viewer shows the not-connected state, never an empty board.
- **Setup:** `herdrdesk-join` against a fake hub (a temporary HOME plus a local sshd, or a stubbed `ssh`) can be run twice without changing anything the second time.

## Open questions

- Should the bridge refuse when the hub GUI app is not running, or work independently of it? Independent is simpler. The design above does not depend on the GUI app.
- How large does the `update` snapshot get on a busy hub, and is a diff needed in phase 1?
- Release channel for viewer installs: copy the hub's build, or use GitHub releases?
