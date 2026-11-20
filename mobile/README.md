# HerdrDesk for iPhone — first development slice

Native SwiftUI client, iOS 17+, with a separately launched Mac relay. No change to
the installed desktop application or Core. This first slice must be runnable in
an isolated Simulator and must distinguish demo data from a live connection.

First UI: teams, group/direct conversations, task states, connection settings,
and the approved sheep artwork. Include loading, empty, disconnected and error
states. Drafts survive navigation; a connection switch must not send an old draft
to a new session. Never show a transport ACK as a completed agent reply.

Relay: Python standard library, loopback-only by default, explicit launch, bearer
authentication, bounded JSON. Fixture mode supports deterministic conversation
and send tests. Optional live read-only mode obtains allowlisted terminal metadata
from hc; it does not read transcripts, private archives, credentials or argv.
Real message delivery is unavailable until the desktop's origin/receipt path is
integrated; the API and UI must advertise that capability honestly.

Production iPhone connections require HTTPS and a paired token. Plain HTTP is
permitted only for simulator loopback development; no arbitrary-loads ATS bypass,
public listener, background service, automatic pairing or Core update.

## Shared API v1

All endpoints except health require `Authorization: Bearer <token>`.

`GET /v1/health` returns only `{"schemaVersion":1,"service":"herdrdesk-relay"}`.
`GET /v1/snapshot` returns the schema below; arrays may be empty.

```json
{
  "schemaVersion": 1,
  "mode": "demo",
  "connection": "live",
  "capabilities": {"readMessages": true, "sendMessages": true, "runtimeApproval": false},
  "teams": [{"id":"herdrdesk","title":"HerdrDesk","memberCount":2}],
  "agents": [{"address":"synthetic-lead","session":"100:1","role":"synthetic-lead","teamId":"herdrdesk","name":"Lead","provider":"codex","status":"working"}],
  "conversations": [{"id":"direct:synthetic-lead","title":"Lead","kind":"direct","teamId":"herdrdesk","address":"synthetic-lead","session":"100:1","role":"synthetic-lead","unreadCount":0}],
  "messages": [{"id":"synthetic-reply","conversationId":"direct:synthetic-lead","role":"assistant","text":"Synthetic fixture","createdAt":"2026-11-20T00:00:00Z","state":"received"}],
  "tasks": [{"id":"synthetic-task","teamId":"herdrdesk","title":"Synthetic task","state":"working","owner":"Lead"}]
}
```

`POST /v1/messages` body:
`{id,conversationId,address,session,role,text}`. `id` is a canonical lower-case client
UUID (the relay also accepts case variants and treats them as the same UUID).
The text limit is 4,000 Unicode code points and the complete JSON body is bounded
to 16 KiB. New clients generate lower-case UUIDs and match the canonical receipt ID.
Response `{id,state,mode}`; fixture accepted state is `demo-accepted`, never
real delivery. Same ID+same payload replays the prior response; same ID+different
payload is 409. A stale address/session/role/conversation is 409. No automatic
retry after timeout. Live read-only mode rejects sends with 403/capability false.
No runtime approval endpoint exists in this slice.

Token is not included in logs, screenshots or fixtures. Client stores it in
Keychain. No external dependencies or production network are required for tests.
