# Discord Status Modifier

A native macOS app that sets a Discord “Playing” rich presence from a library of profiles. It talks to the Discord desktop app over the local RPC unix socket. It never asks for a Discord password, a user token, or a bot token, and it does not implement a self-bot.

Discord Rich Presence only works while the Discord desktop app is running and signed in on the same Mac. If Discord quits or restarts, the app reconnects with backoff and puts the active profile back. Closing the window leaves a menu-bar item so the presence stays up. Quitting the app for real clears the activity.

Requires macOS 14 or later. There are no third-party packages. No developer-portal setup is required: open the app with Discord desktop running and signed in, then pick a profile.

## Artwork

The in-app preview always uses the image on this Mac. A local file is copied into Application Support.

To show that image on Discord, the app publishes it when you set the profile live:

- A file is uploaded anonymously to a public host, starting with [catbox.moe](https://catbox.moe). If catbox refuses the upload (it currently rejects many anonymous clients with “Invalid uploader”), the app tries litterbox, then x0.at, then pixi.mg. The response is a public URL. Anyone with that link can view the file, including GIFs.
- The app then registers the URL with Discord’s external-assets endpoint and sends the returned `mp:external/...` path as `large_image` or `small_image`.
- If you paste an https image link instead of a file, the upload is skipped and only the external-assets call runs. If that call fails, the https URL itself is sent as the image field.
- If the large image is left empty, the app sends a blank image. Discord would otherwise show this application's icon.

## Profiles

Profiles live in `~/Library/Application Support/DiscordStatusModifier/profiles.json`, with copied images under `artwork/`. Each card can set the activity type (None, Playing, Listening, Watching, or Competing), title, details, state, images, up to two buttons, a count-up or count-down timer, party size, and which line appears beside your name in the member list. None is the default on a new card. Setting that card live clears the activity, so Discord shows nothing.

Discord shows buttons to other people, not on your own profile. The editor preview still shows them.

Click a card to send `SET_ACTIVITY` and mark it live. Click it again, or use Stop, to clear the status. The last live profile is restored on the next launch and reapplied once Discord is connected.

Download on a card saves that card as a `.dscard` file you can send to someone else. Upload (in the toolbar, or on the empty library) adds the file as a new card and does not replace one already on this Mac. The file includes the card text and any images stored on this Mac. An https image link is kept as a link and is not copied into the file. Discord’s uploaded-image cache stays on the Mac that published it; the other Mac publishes the image the next time that card is set live.

## Run it in Xcode

1. Open `DiscordStatusModifier.xcodeproj` in Xcode 15 or later on a Mac running macOS 14 or later.
2. Select the **DiscordStatusModifier** scheme.
3. Press Run.

### Build from the command line

If you only have Xcode Command Line Tools (no full Xcode app), run:

```bash
./build.sh
```

The app bundle is written to `build/DiscordStatusModifier.app`. Open it with `open build/DiscordStatusModifier.app`. Full Xcode is still recommended for debugging and asset-catalog icons (`actool`).

The project turns the App Sandbox off so it can reach Discord’s unix socket and make outgoing network calls. Signing is set to ad hoc (`Sign to Run Locally`). If Xcode asks for a Team, you can pick your personal team or leave local signing as-is.

The app looks for IPC sockets `0` through `9` named `discord-ipc`, `discord-ptb-ipc`, `discord-canary-ipc`, and `discord-development-ipc` in the temporary directory, `/tmp`, and the matching Discord Application Support folders. Stable, PTB, Canary, and Development builds are all covered. The first socket that completes the handshake is used. The signed-in user from the IPC `READY` event is shown as “Connected as {display name}” with their avatar.

## Window and menu bar

The game-controller menu-bar item stays after you close the window, and the status stays up with it. Use that menu to switch profiles, stop, or quit. Quitting clears the presence if Discord is still connected. Dock-clicking the app again reopens the window.
