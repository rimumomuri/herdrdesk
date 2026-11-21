# Plan: one hub, HerdrDesk on any Mac

Status: design, not implemented. Nothing in this document changes current behavior.

## Goal

Open HerdrDesk on a second Mac (a laptop, say) and get the same screen as on the main Mac: the same agents, conversations, questions, card board and computer settings, with the same buttons and the same safety rules. A new Mac should be able to join with a single setup step.

Not goals for the first version:
- Running leads on several Macs at once.
- Automatic failover when the main Mac is off.
- Syncing app data between Macs.

## Decision: one hub, every other Mac is a window

One Mac is the **hub**. Leads run there, and every record lives there: the card board, `machines.json`, the answer and send ledgers, results, lineage, handoffs, live-chat state and outgoing history.

Every other Mac running HerdrDesk is a **viewer**. A viewer draws the page and forwards what the person does to the hub. Apart from local preferences (listed below), a viewer keeps no records.

Why not let every Mac keep its own records:
- **Things would be done twice.** The answer ledger, `send.lock` and direct-send ledger are kept per Mac, so two Macs could each answer the same question once. The `ask.state=sending` label is informational only, not a compare-and-set.
- **Records would split.** The hub stores a terminal as `x`, and a viewer sees it as `hub/x`. Lineage identities, epoch hashes, attachment session keys and handoff parties would never match.
- **Some data can only be read on the hub.** Live chat finds each terminal's transcript through the hub's process table:
  - Claude Code: `~/.claude/sessions/<pid>.json`.
  - Codex: `ps` and `lsof` on `~/.codex/sessions`.

  A viewer has none of these.
- **User-facing replies are matched per process.** A reply is marked user-facing by matching a receipt armed by the sending process against the transcript that same process reads. The receipt is keyed by a per-process UUID and stored in the local `user-dispatch/`. So the sender and the transcript reader must be the same long-lived process on the same Mac.

## Approaches considered

**A. Redirect each feature to the hub (rejected).** This means reading the card board, results and transcripts through `hc exec --on` / `hc file read --on`, one feature at a time. It was rejected because:
- More than ten separate call sites would change.
- The duplicate-answer and address-mismatch problems above would still need separate fixes.
- Live chat would need a remote `ps`/`lsof` walk every few seconds.

**B. One hub controller, with every window as a client (chosen).** The app already has two narrow seams:
- **Page to app:** one message handler, `webkit.messageHandlers.desk`.
- **App to page:** one `call(script, args)` helper for every `desk.*` callback.

In this approach the controller runs only on the hub, and only those two seams cross the network.

## Architecture

```
viewer Mac A ─┐                hub Mac
              │ ssh (restricted key)  ┌────────────────────────────────────────────┐
viewer Mac B ─┼─► HerdrDesk --bridge ─┤ HerdrDesk app (the one controller)         │
              │   (transport only,    │  hub window ─ local sink                   │
              │    one per viewer)    │  bridge sockets ─ remote sinks             │
              └──────────────────────►│  hc, herdr-task, ledgers, live chat,       │
                                      │  lineage, results, outgoing history        │
                                      └────────────────────────────────────────────┘
```

### The controller is owned by the hub app, not by a connection

The HerdrDesk app on the hub is the only controller. It owns:
- every send;
- the `UserDispatchReceipts` generation;
- live-chat reading;
- the in-memory handoff and live-reply state.

Its lifetime does not depend on any viewer. A viewer can send a request and close its window before the agent finishes. The hub app keeps observing, claims the receipt it armed, and records the reply as user-facing. A viewer that opens later sees the finished conversation.

- **Local socket:** the hub app listens on a Unix socket, `client.sock`, in its data folder. The folder has mode 0700 and the socket 0600. On every connection the app checks that the peer runs as the same user (`getpeereid`).
- **Hub app not running:** the bridge launches it hidden with `open -g -j -b <bundle id>`, then waits for the socket. The app keeps running until someone quits it. That is the same as opening it by hand: it is not a LaunchAgent, and it does not start at login.

### `HerdrDesk --bridge` is transport only

This is a headless mode of the same executable, like the existing `--lineage` mode. It does the following:
1. Connects to `client.sock`.
2. Copies JSON lines between SSH stdio and the socket.
3. Exits when either side closes.

It holds no state, sends nothing by itself, and never touches app data. A dropped connection loses nothing except that viewer's view.

SSH is the transport because it gives a full-duplex byte stream, with key authentication that the setup step already arranges. `hc exec` returns one result per call and is not a stream. An `hc connect`-based transport could replace SSH later without changing the protocol.

### Protocol (JSON lines, one object per line)

- **Handshake:** the first message from the hub is `hello`. It carries the app version, the protocol version, the hub's machine name and this client's granted access (see below). If the versions do not match, the viewer shows "update HerdrDesk on the hub" and stays read-only.
- **Client to hub:** `{"t":"page","id":…,"body":{…}}`. The body is exactly the message the page posted (`ready`, `send`, `answer`, `approval`, `machine`, `terminalWatch`, and so on). The viewer never builds hc commands.
- **Hub to client:** `{"t":"call","fn":…,"args":{…}}`. Every `call(script, args)` the controller makes becomes one of these.

### Every open window sees committed changes

The controller keeps a list of sinks: the hub window plus one per connected bridge. Calls are routed as follows:

| Call | Goes to |
|---|---|
| `update` (snapshot) | **All sinks.** Each one receives the same snapshot on every change, and the full snapshot when it connects. |
| `notice`, `compatibilitySummary` | All sinks. |
| `sendResult`, `questionResult`, `approvalTarget`, `machineResult`, `attachmentResult`, `chatImages` | Only the sink whose request `id` caused the call. The state change itself reaches everyone through the next `update`. |
| `terminalEvent`, `terminalOutput` | Only the sinks watching that terminal. Each sink has its own flow-control credit: `terminalOutput` waits for that sink's `{"t":"ack"}`, so a slow viewer does not stall the others. |

This works because shared state moves out of the page and into the controller. Today the page keeps these in WebView `localStorage`. They are split as follows:

| Kept on the hub (in the snapshot) | Kept per window (stays in `localStorage`) |
|---|---|
| Outgoing history (`deliveries`, legacy `ownMessages`) | Composer drafts |
| Handoff history (`team.handoffs`) | Language, sounds |
| | Pins, chat sections, chat preferences, character choices |

Shared items:
- The controller writes outgoing and handoff history to app data, with the same caps as today (200 deliveries).
- On a window's first connection after upgrading, the page offers its existing `localStorage` history to the controller once. The controller merges it by message id.

Per-window items:
- **Drafts are deliberately per window.** Two people typing on two Macs should not overwrite each other. Attachment drafts follow the window that holds the draft.
- Display preferences are per window for now. Sharing them can come later without a protocol change.

### Addresses

The controller runs on the hub, so every address it handles is the hub's bare address. Records match with no translation. The `hello` message includes the hub's machine name, and the page uses it as `localMachine`, so devices are labelled correctly. Today `localMachine` is never sent; this work fixes that.

### What stays on the viewer

| Feature | Viewer behaviour |
|---|---|
| Window-key and app-active checks for `machine`, `terminalInput`, `copyChatID`, link opening | **A local UI guard only.** The viewer checks it before forwarding. The hub cannot verify it and does not rely on it. What a viewer may do is enforced on the hub by its granted access (below). |
| `HERDRDESK_NO_SEND=1` | Honoured on the viewer: it forwards nothing that sends. |
| Sounds, language, appearance, drafts | Local. |
| Attachments | The file is on the viewer. The viewer streams it in chunks (`{"t":"file",…}`). The controller writes it into the hub's `attachments/` and continues as today. |
| Image thumbnails (`chatImages`) | Read on the hub by the controller and returned as data. The current folder rule is unchanged. |
| `herdrdesk-path:` links | A hub path cannot be opened on the viewer. The viewer offers to copy the path, or to fetch a copy of the file through the controller (read access required). |
| `open` (focus the terminal in Herdr) | Works only if this viewer's own Herdr is connected to the hub (an optional full-trust setup, below). Otherwise the button explains why it is unavailable. |

### Stores on the hub

There is one controller, so the multi-writer problems of a per-connection design go away. What is still needed:

| Store | Needed |
|---|---|
| `send.lock`, answer and direct ledgers | Unchanged. Only the hub controller sends, so a question answered from any window is answered once. |
| `user-dispatch/` receipts | Unchanged. The long-lived controller arms and claims them. |
| `live-replies.json`, `handoffs.json`, `lineage/state.json`, new history files | Written only by the controller. Hub agents still write lineage through `--lineage`, which already uses `write.lock`. The controller already re-reads lineage when its mtime changes. |
| `herdr-task` (`machines.json`, `state/`) | Unchanged. It has its own `spawn_lock`. |

## Access a joined Mac gets

A plain `ssh-copy-id` would give the new Mac a full login as the hub user. Joining HerdrDesk must not do that by default.

- **Restricted key.** `herdrdesk-join` registers the viewer's key in the hub's `~/.ssh/authorized_keys` as a forced-command entry:

  ```
  restrict,command="'/Applications/HerdrDesk.app/Contents/MacOS/HerdrDesk' --bridge --access=operate --client=<name>" ssh-ed25519 AAAA… herdrdesk:<name>
  ```

  `restrict` turns off port, agent and X11 forwarding and the PTY. The key can only start the bridge. It cannot open a shell, copy files or run other commands.
- **Revocable.** Removing that one line revokes the Mac. The key comment `herdrdesk:<name>` lets a later `herdrdesk-join --revoke <name>` find it.
- **Enforced on the hub.** The bridge passes `--access` and `--client` to the controller when it connects. The controller checks each page message against the access level:

  | Access | Allowed |
  |---|---|
  | `view` | `ready`, `refresh`, `terminalWatch`/`Unwatch` (read only), `chatImages`, reading attachments and links |
  | `operate` (default for join) | Everything in `view`, plus `send`, `answer`, `approval`, `attach`/`detach`, `terminalInput` |
  | `admin` | Everything in `operate`, plus `machine` (computer settings, clone, unlink) and `chooseCore` |

  A refused message gets an error result and is logged with the client name. Window focus is never treated as authority.
- **Card workers, the other direction.** The hub also needs to place card workers on the new Mac (hub → Mac). That uses the hub's key in the new Mac's `authorized_keys`, which is what card placement needs today. That key is a normal login, because workers run real commands there. The setup step states this plainly.
- **Optional full trust.** Adding the hub to the viewer's own Herdr (so the Herdr app can show hub terminals, and `open` works) needs a normal login on the hub. It is a separate opt-in step in `herdrdesk-join` (`--full-login`), never the default.

## New Mac setup: `herdrdesk-join`

`herdrdesk-join` is a script that runs once on the new Mac:

1. Check that Tailscale (or another route to the hub) and Herdr are installed.
2. Create `~/.ssh/id_ed25519` if it is missing. Register it on the hub as the **restricted** entry above, with access `operate` (or as chosen with `--access`). **The person types the hub password once here.** The script logs in once with a password to append the line, and never installs an unrestricted key unless `--full-login` is given.
3. Add the hub's public key to this Mac's `authorized_keys`, for card workers.
4. Add this Mac to the hub's Herdr machine list (`hc machine add`, run on the hub through the step-2 login).
5. Write `hub.json` on this Mac: `~/Library/Application Support/app.herdrdesk/hub.json`, holding `{"ssh":"user@host","bundle":"…"}`. If the file is missing, the Mac is a hub and works exactly as today.
6. Install HerdrDesk.
7. Add this Mac to the hub's `machines.json` with `herdr-task machine add`, which is new. It starts **not ready**, with 0 slots.

Each step prints what it did. The script stops at the first failure, and every step can be run again safely.

After setup, the rest happens in HerdrDesk on any Mac: turn the computer on, set its slots, and "receive" team repos. These need `admin` access. The person logs in to the AI apps (Claude, Codex) on the new Mac themselves.

### Viewer screens

| State | What the viewer shows |
|---|---|
| Waiting for `hello` | "Connecting to the hub" |
| Hub not reachable | "Hub not connected" and the last error. It never shows an empty board as if nothing were running. |

While the window is open, the viewer retries after 5s, then 15s, then every 60s. It never retries while the app is closed.

## Later: moving the hub

Moving the hub means moving where the leads live. It is a deliberate manual operation, never automatic. If it were automatic, a hub that was only asleep would get a second hub beside it.

1. Pause new assignments on every team. Running cards finish or stop.
2. Copy these to the new hub, and verify each copy:
   - the leads' agent sessions (`~/.codex`, `~/.claude` project files);
   - the card board and `machines.json`;
   - app data, including the shared history and results;
   - the team repos.
3. Start the leads on the new hub by resuming their existing sessions.
4. Re-run `herdrdesk-join` from each viewer against the new hub.
5. Add the old hub to `machines.json` as an ordinary computer for card workers.

Neither Mac makes new assignments during steps 1 to 3. This is the same rule the existing lead hand-over (authority epoch) follows.

## Phases

1. **Controller and viewer.**
   - Client socket and sink list in the hub app.
   - `--bridge` transport.
   - Viewer mode driven by `hub.json`.
   - Hub-backed outgoing and handoff history.
   - Access enforcement, attachment streaming and `localMachine`.
2. **Setup.** `herdrdesk-join` (restricted key, revoke) and `herdr-task machine add`.
3. **Moving the hub.** A helper and a runbook.

## Testing

- **Survives disconnect.** Viewer A sends, then disconnects right after dispatch. The (fake) agent finishes. Viewer B connects and sees the reply, classified as user-facing. The receipt is claimed exactly once.
- **Live update across windows.** Viewers A and B are both open. A sends a message. Without a reconnect, B's next `update` contains the delivery and the reply. A's `sendResult` goes only to A.
- **One send.** A and B answer the same question at the same time. Exactly one `hc send` runs (fake `hc`). The other gets an "already answered" result.
- **Access.**
  - A `view` client's `send` is refused on the hub.
  - An `operate` client's `machine` is refused.
  - The focus flag in a forged message does not change either result.
- **Restricted key.** With the forced-command line installed, `ssh hub ls` runs the bridge rather than `ls`, and port forwarding is refused. Test against a local sshd in a temporary HOME, or check the generated line exactly.
- **Bridge.**
  - The bridge exits on EOF from either side.
  - A peer running as a different user is refused on `client.sock`.
  - A version mismatch leaves the viewer read-only.
  - The bridge starts the hub app when it is not running.
- **Flow control.** A slow viewer watching a terminal does not delay `terminalOutput` to another viewer.
- **History migration.** `localStorage` history offered by two windows merges by id without duplicates.
- **Hub not reachable.** The viewer shows the not-connected state, never an empty board.
- **Setup.** Running `herdrdesk-join` twice changes nothing the second time. `--revoke` removes only that client's line.

## Open questions

- How large does the `update` snapshot get on a busy hub with several viewers? Is a diff needed in phase 1?
- Release channel for viewer installs: copy the hub's build, or use GitHub releases?
- Should display preferences (pins, sections) become shared later, or stay per window?
