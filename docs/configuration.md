# Configuration

## Core and desktop app

HerdrDesk uses your existing Core session. Install Herdr separately using its official instructions. If discovery fails, choose an executable named `hc` in HerdrDesk. For a development launch from a shell you can set `HERDRDESK_HC` to an absolute path. That override starts a fixture-style app instance with temporary WebKit preferences. `HERDRDESK_APP` can specify the absolute path to `herdr-app`.

Use Herdr to add, authenticate and remove remote machines. A Core terminal can remain visible even when no space or tab has been assigned in the Herdr window.

## Teams and names

The app discovers all live Core terminals and uses Herdr's space and tab names when available. Labels are optional. For example, to group two of your own test terminals:

```sh
hc label t1 team.id=project team.title=Project display.title=Coordinator
hc label t2 team.id=project team.title=Project display.title=Reviewer
```

A parent indicator comes from Core's recorded terminal parent. Group membership and parentage do not imply a completed handoff.

## Language and data

Change the language using the selector in the app. The selected language is stored per installation. Existing team names, paths, message content and terminal output remain in their original language. Test with a separate `HERDRDESK_DATA` directory and a separate Core session when checking send behavior.

## Questions and approvals

Assign a unique `recovery.role` label to each participating coding agent. From inside the requesting Herdr terminal, run `cli/herdr-ask open --text "Which build should I use?"`. A question can carry an optional `--approval-role ROLE` that links to a separate terminal. HerdrDesk can open that terminal after validating the link and session. Actual approval is handled by Herdr. The requesting agent can mark an answered question as received with `cli/herdr-ask ack QUESTION_ID`.

To publish a reply explicitly from a role-labelled agent on the desktop Mac, run `cli/herdr-reply --text "Preview tested"` from its Herdr terminal. It writes a local reply record that the app can display. Records created on remote Macs are local to the remote Mac unless the deployment provides a shared reply directory; this preview does not collect remote assistant transcripts.

### Team conversations

The Team Chats view sends to the team's unique live lead and keeps direct messages in their existing conversations. Set the `team.id` label on team members and `team.lead=true` on their lead for setups without a team configuration. The app leaves the composer disabled when the lead cannot be resolved uniquely.

To share a message explicitly with a team, run the bundled `herdr-team-message --team TEAM_ID --text "Preview tested"` from your own role-labelled Herdr terminal. The repository helper also accepts `cli/herdr-reply --team TEAM_ID --text "Preview tested"`. The record goes to the local HerdrDesk results directory, or to the configured `HERDRDESK_RESULTS` directory. The team ID must match a team the publishing role belongs to. A share creates a timeline entry and does not deliver a message to another agent. Use the usual Herdr delivery workflow for assignments.

Team chats show sends initiated in that team view, explicit team shares, and recorded same-team handoffs. Private replies and terminal output remain in their respective views. Question and approval alerts appear inside the app and link to the question or its verified Herdr terminal.
