# bean'd

**bean'd** is a free, open-source app for tracking coffee: espresso shots
from [Meticulous](https://meticuloushome.com) and
[GaggiMate](https://gaggimate.eu) machines, and pour-over brews with an
Acaia scale over Bluetooth. It keeps a local archive of every shot and bean,
independent of the machine, and can optionally sync between your own devices
end-to-end encrypted over Nostr.

> bean'd is an independent open-source project and is not affiliated with
> any of the manufacturers mentioned. All trademarks belong to their
> respective owners.

<!-- TODO: screenshots -->

## Features

- **Live shot view** for Meticulous and GaggiMate: pressure, flow, weight and
  temperature, preheat ETA, start/stop from the phone.
- **Shot history** that never disappears: shots are imported from the
  machine and kept locally, with filters, detail view, side-by-side compare,
  ratings and notes.
- **Shot findings** without AI: stage-by-stage checks (stalls, channeling,
  off-target stages), plus optional AI analysis with your own API key
  (Anthropic, OpenAI, Gemini, OpenRouter or a custom endpoint).
- **Beans**: roaster, origin, roast date, photos, remaining amount; fill the
  form from a photo or a shop page.
- **Profiles**: view, reorder, upload and build profiles for both machines,
  with checks that keep the machine from getting stuck.
- **Pour over** with Acaia scales (Lunar, Pearl, Pyxis …): live weight and
  flow, recipes, pre/live/post brew.
- **Share a shot** as an image.
- **Sync** between your own devices: end-to-end encrypted (NIP-44) over
  Nostr relays and Blossom servers; public relays by default, or your own
  server ([beand-server](https://github.com/tangenzzz/beand-server)).
- **Backup/restore** of everything to a single zip file.

## Supported hardware

| Device | Connection |
|---|---|
| Meticulous | Socket.IO + REST over Wi-Fi, mDNS discovery |
| GaggiMate | WebSocket over Wi-Fi, mDNS discovery |
| Acaia scales | Bluetooth LE (old and new firmware) |

Android is the main platform. iOS builds from the same code but has not been
tested yet.

## Building

Requirements: Flutter (stable, Dart SDK ^3.13), Android SDK.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Release signing: create `android/key.properties` pointing to your own
keystore (see the comment in `android/app/build.gradle.kts`). Without it the
release build is signed with the debug key.

To update the app on a device without losing data, use
`adb install -r <apk>`. `flutter install` uninstalls the app first and wipes
its database.

## Project layout

| Path | Contents |
|---|---|
| `lib/screens/live` | Home screen per mode (Meticulous, GaggiMate, Pour Over): live sensors, preheat ETA, pre/live/post shot flow |
| `lib/screens/history` | Shot archive: list, filters, detail, compare |
| `lib/screens/beans` | Bean list and form |
| `lib/screens/profile` | Profile view and editor |
| `lib/screens/settings` | Connections, appearance, AI, sync, backup |
| `lib/machines`, `lib/scale` | GaggiMate and Acaia integration |
| `lib/services` | Meticulous connection, shot/brew logic, AI, backup |
| `lib/sync` | Encrypted sync over Nostr and Blossom |
| `lib/database` | Local database (Drift/SQLite) |
| `tool/` | Helper scripts (connection tests, icon generation, recipe update) |

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).
For security issues, see [SECURITY.md](SECURITY.md).

## Credits

bean'd builds on the work and documentation of others:

- [tatemazer/AcaiaArduinoBLE](https://github.com/tatemazer/AcaiaArduinoBLE)
  (MIT): Acaia BLE protocol.
- [hessius/MeticAI](https://github.com/hessius/MeticAI) (MIT): rules and
  thresholds for the shot findings.
- [HotThoughts/brew-recipes](https://github.com/HotThoughts/brew-recipes)
  (CC0): bundled pour-over recipes.
- [MeticulousHome/espresso-profile-schema](https://github.com/MeticulousHome/espresso-profile-schema),
  [pyMeticulous](https://github.com/MeticulousHome/pyMeticulous) and
  [meticulous-backend](https://github.com/MeticulousHome/meticulous-backend):
  profile format and machine API.
- [twchad/meticulous-mcp](https://github.com/twchad/meticulous-mcp): profile
  validation rules (rewritten, not copied).
- [nickwilsonr/meticulous-addon](https://github.com/nickwilsonr/meticulous-addon):
  preheat detection.
- [GaggiMate](https://github.com/jniebuhr/gaggimate): machine API.
- [Nostr NIPs](https://github.com/nostr-protocol/nips),
  [paulmillr/nip44](https://github.com/paulmillr/nip44) test vectors and
  [Blossom](https://github.com/hzrd149/blossom).
- [Barista Hustle Coffee Compass](https://www.baristahustle.com/blog/the-coffee-compass/):
  the idea behind the taste feedback.
- Wordmark set in [Archivo](https://fonts.google.com/specimen/Archivo)
  (SIL Open Font License).

The licenses of all bundled packages are listed in the app under
Settings → About → Open-source licenses.

## License

bean'd is licensed under the [GNU General Public License v3.0](LICENSE).
