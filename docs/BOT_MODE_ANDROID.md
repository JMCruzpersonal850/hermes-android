# Android Bot Mode

This fork is adding a native Bot Mode surface to the existing Hermes Android client.

## Architecture

- **Hermes on the PC remains the runtime.** Android is a first-class remote client.
- **Hermes profiles are bots.** Android reads and creates them through the Desktop Gateway `profiles.*` JSON-RPC family; it does not maintain a second bot database.
- **The canonical chat is authoritative.** `profiles.list` supplies `canonical_session` for each profile's one `Bot Chat`. Android should open that session in the target profile rather than minting arbitrary side chats.
- **Older gateways degrade cleanly.** If `profiles.list` is unavailable, the UI should explain that the PC Hermes install needs an update instead of crashing.

## Phase 1 (current branch)

- `HermesProfile` and canonical/worker session models.
- `ProfilesGatewayClient` for `profiles.list`, `profiles.create`, `profiles.describe`, and `profiles.configure`.
- `BotsPane`, a mobile-first roster with create-bot flow, model/skill metadata, working status, refresh, and compatibility messaging.

## Integration still required before shipping the APK

1. Add **Bots** as a top-level `HermesDestination` between Chats and Projects.
2. Expose `ProfilesGatewayClient` from `DesktopGatewayClient` using the existing authenticated control WebSocket.
3. Wire `BotsPane` in `WorkspaceScreen`.
4. Make bot-chat open/resume profile-aware. A Bot Chat belongs to its Hermes profile; session resume/create and history hydration must preserve that profile scope.
5. Implement safe canonical Bot Chat creation for newly created profiles using the same identity rule as Hermes Desktop (`title == "Bot Chat"`, hidden, fail closed when registry lookup is inconclusive).
6. Add profile avatar retrieval/editing through `profiles.get_asset` / `profiles.set_asset`.
7. Add edit-bot UI and, after the single-bot path is stable, bot-to-bot/group-room UI using the gateway bot relay contract.
8. Run Flutter analyze/tests, build a debug APK, and test against a current Hermes Gateway on the PC.

## Non-goal

The unrelated Android Accessibility "Hermes Bridge" is not required for this app. It can remain installed separately if phone-control features are wanted later.
