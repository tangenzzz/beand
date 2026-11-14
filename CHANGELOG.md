# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
