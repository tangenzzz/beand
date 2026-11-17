# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Introduction: every screen it opens has Continue at the bottom (also on
  the Meticulous, GaggiMate and Scales pages); the back arrow returns to the
  same introduction page.
- Value ruler: drag anywhere on the panel, including the big number; the
  keyboard icon still opens the input.
- Beans: the currency moved to Settings → Beans → Form, under Cost.
- Grinders: clicks read either as plain clicks (Comandante, "45") or as
  rotations, now also rotation.number.click (1Zpresso K-Ultra). With
  rotations you pick how many the dial turns instead of From/To; with one
  the reading leaves the rotation out ("4.6"), with more it leads ("1.4.6")
  and Pre-Shot offers the rotations above the grind ruler.

### Fixed
- Pre Shot: a profile started on the machine now brings its bean, dose and
  grind even when the Pre Shot card was not in view.

## [0.9.2] - 2026-11-14

### Added
- Beans: choose the currency of bean prices.

### Changed
- Pre Shot: switching the profile brings back the last coffee used with it,
  with its dose and grind.
- Profiles: the list follows changes made on the Meticulous, and the Add
  profile dialog reloads it from the machine.
- Sync: appearance settings stay per device.
- Android: camera, Bluetooth and location are optional, so Google Play no
  longer hides the app on devices without them.

### Fixed
- Live: the machine's water check counts as preparation, not as a running
  brew.
- Backup: password fields stay out of autofill, and Next moves to the repeat
  field.

## [0.9.1] - 2026-11-12

First public release (pre-release).

[0.9.2]: https://github.com/tangenzzz/beand/releases/tag/v0.9.2
[0.9.1]: https://github.com/tangenzzz/beand/releases/tag/v0.9.1
