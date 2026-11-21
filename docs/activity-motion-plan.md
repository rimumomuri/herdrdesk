# HerdrDesk activity and character motion

## Interaction

Team and personal conversations share one list. Pin a conversation to place its character tile in the shelf above the scrolling recent list. Unpin it to return it to the recent list. A team’s composer sends to the registered lead. Open Members to see the full roster and select a member’s personal conversation. An arrow pulses on a recorded handoff or acknowledgment. Blue indicates a confirmed send and green indicates recorded receipt. Approval requests remain amber.

The [Grok Bot changelog](https://x.ai/changelog/bot) describes an animated avatar and an activity line that stay visible while a bot works without a reply. Those are the two interaction patterns to adapt. The [Apple Motion guidelines](https://developer.apple.com/design/human-interface-guidelines/motion) inform the pace and reduced-motion treatment.

## Character and motion

Use an original, side-facing sheep with rounded wool, a slate face, one ear and two feet. Cream, oat and pale lilac coats help identify teams at a glance. Keep Codex and Claude Code logos in the conversation header and directory.

| Herdr signal | Character and feedback |
| --- | --- |
| Work sent or assigned | Start the recipient’s motion for one 3.2-second loop after Herdr reports the send or records the assignment. Use the existing delivery status for receipt confirmation. |
| Live and working | Each recognized agent uses a cream sheep portrait holding its provider logo inside its mouth. This follows the HerdrDesk app icon. The active portrait blinks and chews lightly with the orange bead orbiting in front of and behind it. The provider logo stays visible. Keep the provider name in the activity text. Agents without a recognized provider use the neutral sheep for activity. |
| Idle or disconnected | The sheep rests beside the state label and keeps the provider logo in its mouth. |
| Recorded handoff or reply | Show a compact sender-to-recipient row. The sheep passes a paper card once when the row arrives. Open Shared & Handoffs for the full timeline. |
| New question or approval | The question card appears in its conversation. The conversation list keeps a static amber count until the request is handled. |
| Unread result or share | A blue dot shows that the corresponding chat or timeline has something new. Working, unread and pending approval are independent states. |
| Reduced motion | Keep the same static sheep and state text. No movement is required to interpret a state. |

Show the larger sheep only beside the active conversation. The sidebar uses a reduced silhouette and compact indicators. The status is based on Herdr's reported state, with no simulated progress percentage.

## Sound and interim messages

Sound effects are enabled by default and can be muted in Settings. HerdrDesk plays a short cue after a confirmed send and a distinct cue when Herdr reports a completed agent turn. Opening the app or reconnecting establishes a fresh status baseline. The completion cue depends on Herdr providing a completion status.

Use the bundled `herdr-progress --text "The existing sessions have resumed."` from a registered agent session to publish a progress note. Add `--team TEAM_ID` when it should also appear in the group chat. To copy an already-sent agent message into the recipient's chat, use `herdr-progress --handoff-to ADDRESS --body-file /absolute/message.txt` after delivery is confirmed. The publisher checks the current sender and recipient through Herdr and performs no send. Recorded Herdr work assignments and handoff summaries also appear in the recipient's chat.

Progress notes and handoffs have quieter styling and their own labels. Final replies keep their existing appearance. HerdrDesk does not import terminal scrollback, raw tool activity, or historical chat transcripts. Explicit publication is also available for sessions without automatic capture.

## Automatic live chat

HerdrDesk can follow typed records appended to a registered local agent's current conversation while the app is running. It begins at the end of each newly attached file. Codex progress requires assistant commentary. Claude Code progress requires visible assistant text followed by a tool call in the same message. A Herdr handoff requires a transport envelope with a matching address and a unique currently registered sender and recipient. The receiver's personal chat shows the handoff, and the group chat shows it when both endpoints belong to that group. The lead's live progress also appears in the group chat.

The app keeps a bounded in-memory list of the latest captured messages. The toggle **Live chat messages** in Settings stops capture and clears that list. The app does not import historic provider records or terminal screen output. Tool calls, command output, reasoning and ordinary provider input are excluded. Provider records on other computers require a local capture integration on those computers.

## The chat workspace

Open a team or a personal conversation from the sidebar. The chat shows requests, progress, handoffs and published replies. The team owner still receives messages from the group composer. The Settings menu holds the overview, organization, handoff and work views.

Open the selected session with **Terminal**. A linked approval card opens the same drawer with the validated target while keeping the current chat visible. Scroll up to read recent output. Use **Latest** to resume following the terminal. Click the terminal to focus it for typing or pasting. Keyboard input only reaches the exactly bound live session while the app’s window is active and the terminal has focus. Use the real prompt to review and decide on an approval.

## Conversation hierarchy

The sidebar uses a composite thumbnail for teams and an individual character for each personal conversation. A team row shows its member count and a recent message, handoff, or reply. The roster opens beside the chat from Members. Status dots show activity and glow while an agent is working.

Requests, handoff messages, replies, and approval actions remain visible in the conversation. Progress entries show a one-line preview and can be expanded with a click or keyboard. Terminal access stays beside the current conversation. Work continues on the existing Herdr host and depends on that host's availability.

[Designing Grok Bot for a world of persistent agents](https://x.ai/news/designing-grok-bot)
