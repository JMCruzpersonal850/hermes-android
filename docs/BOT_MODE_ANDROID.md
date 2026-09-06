# Android Bot Mode

This fork adds a native, profile-aware Bot Mode to the Hermes Android client while keeping Hermes on the PC as the runtime.

## Architecture

- **Hermes on the PC remains the brain/runtime.** Android is a first-class remote client.
- **Hermes profiles are bots.** Android reads and creates them through the Desktop Gateway `profiles.*` JSON-RPC family; it does not maintain a second bot database.
- **The canonical chat is authoritative.** Each bot owns one hidden conversation titled exactly `Bot Chat` in that profile.
- **Profile scope is preserved on mobile.** Canonical lookup, `session.resume`, `session.create`, and prompt streaming all stay on the selected bot profile so one bot cannot accidentally open another profile's state.
- **Canonical creation fails closed.** If Hermes previously reported a canonical Bot Chat but an exact-title lookup cannot confirm it, Android asks the user to retry instead of minting a duplicate chat.
- **Older gateways degrade cleanly.** If `profiles.list` is unavailable, the UI explains that the PC Hermes install needs an update instead of crashing.

## Current test implementation

The `feature/bot-mode` branch now includes:

- `HermesProfile` plus canonical, latest, and worker session models.
- `ProfilesGatewayClient` for `profiles.list`, `profiles.create`, `profiles.describe`, and `profiles.configure`.
- `BotsPane`, a mobile roster with create-bot flow, model/skill metadata, activity preview, working state, refresh, and compatibility messaging.
- `BotModeGateway`, an authenticated profile-scoped WebSocket transport for canonical Bot Chat lookup/create/resume and prompts.
- `BotChatScreen`, a native profile-aware bot conversation with streamed assistant output, basic approval handling, tool/subagent status, and Stop.
- New bots receive the same one-time `Hey, tell me about yourself!` kickoff used by Hermes Desktop so the lazily-created canonical Bot Chat is persisted and the bot can introduce itself.
- Bot Mode is reachable in the current app at **More → Bots & skills → Bots**.
- A branch-only GitHub Actions workflow analyzes, tests, builds an arm64 debug APK, and publishes it as the `hermes-bot-mode-arm64-debug` artifact.

## Before merging to main

1. Enable GitHub Actions on the fork if GitHub has disabled workflows for the newly-created fork.
2. Run static analysis and the full Flutter test suite.
3. Produce the debug arm64 APK and install it on a Galaxy/Android test device.
4. Verify against a current Hermes Gateway on the PC:
   - roster matches Desktop profiles,
   - creating a bot creates a PC Hermes profile,
   - tapping a bot opens/resumes that bot's canonical `Bot Chat`,
   - old messages are present,
   - prompts stream correctly,
   - approvals and Stop work,
   - reopening the bot does not create a second canonical chat.
5. Keep PR #1 draft until the above test passes.

## Follow-up polish after the first APK works

- Promote **Bots** to a dedicated bottom-navigation destination.
- Reuse the full mobile chat feature set in profile-aware Bot Chat: attachments/camera/files, voice, model/thinking picker, clarify/sensitive prompts, notifications, and durable turn recovery.
- Add profile avatar retrieval/editing through `profiles.get_asset` / `profiles.set_asset`.
- Add edit-bot UI.
- Add Bot Rooms / team chat after the single-bot path is proven stable.

## Non-goal

The separate Android Accessibility "Hermes Bridge" is not required for this app. It can remain installed separately if phone-control features are wanted later.