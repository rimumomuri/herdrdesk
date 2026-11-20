# Explicit request lineage

New composer sends retain `conversationId`, the original `m…` message ID and exact recipient address/session/role. The wire contains an origin metadata header. This creates only a root, not a task, delegation, acceptance or completion. Older messages are never assigned a root by role, selected chat or terminal ancestry.

`Contents/Resources/cli/herdr-lineage` is a one-shot helper. It reads one JSON object from stdin and invokes the bundled executable without opening the GUI. A repository checkout can set `HERDRDESK_LINEAGE_TOOL` to the pinned executable. The caller must be an existing live agent identified by `HC_TERMINAL_ID`; the helper re-reads its current `hc get` metadata. This is a local same-user coordination contract, not authentication against other processes running as that user. All participants need the same explicit local lineage store; a remote participant without it stays unlinked.

Operations (every operation requires `originRequestId`):

| Operation | Required metadata | Effect |
| --- | --- | --- |
| `task` | `taskId`; optional `parentTaskId`, `owner:{address,session,role}`, `expiresAt` (epoch milliseconds) | Registers a task. Root task belongs to the original recipient; only a parent task's owner can register its child. Explicit owner is revalidated. |
| `edge` | `edgeId`, `parentTaskId`, `childTaskId` | Registers delegation intent only. |
| `delegate` | `edgeId`, `text` | Revalidates the receiver and invokes the existing `hc send` exactly once. Adds explicit root/task/parent/edge metadata; does not persist `text`. Records only transport outcome, not acceptance or completion. An uncertain or failed attempt is never automatically retried. |
| `accept` | `taskId` | Current task owner explicitly reports receipt. A child requires an attempted registered edge. |
| `complete` | `taskId` | Current task owner explicitly reports completion after acceptance. Does not assert independent product verification. |
| `pending` | `pendingId`, `taskId`, `requestId` | Links the caller's current explicitly registered ask and freshly bound target. Does not create or resolve an approval. |

The recipient reads the IDs in the delivered header and explicitly calls `accept`; it later calls `complete` only after its work is done. Registration never implies these events. No shared flow/ask/assignment tool, watcher, Core behavior or provider bridge is changed. Commands do not collect terminal history. Only the explicit `delegate` operation sends text to another existing agent; the other operations write metadata and notify the existing inventory event path with a revision label.

Roots expire after seven days; child expiry cannot exceed parent/root expiry. IDs are unique, depth is limited to 16, and cross-root, cycle, duplicate, stale owner/session and expired registrations are rejected. The private metadata store is bounded (500 roots, 4000 tasks/edges/pending links, 2 MiB); storage failure prevents registration rather than inventing a link.

The snapshot renders the tree only inside the exact original message in the exact conversation. Manual asks remain labelled as registered questions with runtime approval unverified. Unregistered native blocked states are never linked to a task automatically. Unlinked waiting items remain separate. Resolved/expired asks disappear and changed bindings are rejected on target-open clicks; there are no approve/deny buttons.

An Answer send adds continuation metadata only when its existing ask, task, root, requester and target/session link is complete and current. It otherwise sends the ordinary answer without assigning an origin. This does not change question IDs, approval targets or delivery ledger state.
