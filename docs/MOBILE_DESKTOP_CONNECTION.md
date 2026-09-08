# Connect Android to the desktop service

Hermes has two endpoints. The API server (normally port 8642) provides chat
history and the basic chat API. The desktop service (normally port 9119)
provides profile bots, projects, skills, and the desktop WebSocket protocol.
An API connection alone does not establish the desktop connection.

For a PC reached through Tailscale, run the native `hermes serve` service on
its Tailscale address with a configured password authentication provider.
Do not expose an unauthenticated dashboard to the internet. The installed
Hermes version may require authentication even when `--insecure` is given.

In Android, return to the saved connections list, open the connection's menu,
and choose **Dashboard / Proxy Settings**. Set its desktop port, username and
password, then save. Saving validates the desktop connection. Reopen the
connection to load projects and desktop features.

If your desktop service was deliberately provisioned with username `hermes`
and the same password as your Gateway API key, **Use saved Gateway key** fills
those fields without displaying or copying the key. This is an explicit
shortcut; the app never tries the Gateway key against a dashboard automatically.
For any other service, enter its actual username and password.

The **Bots & Skills** robot button is visible in the Home toolbar. Bots use the
server's profiles, not a separate mobile roster. Chat history follows all REST
pages, including older desktop conversations. Projects require the desktop
service and may be empty even when unassigned chats exist.

Keep Tailscale connected on both devices. The PC must be awake. To verify remote
access, turn phone Wi-Fi off and use cellular data.
