# Contributing to bean'd

Thanks for your interest! Bug reports, ideas and pull requests are welcome.

## Reporting bugs

Open an issue with:
- what you did, what you expected and what happened,
- app version (Settings → About), phone model and Android version,
- the machine or scale involved (model and firmware, if known).

Please do not post API keys, sync keys (nsec) or backup files in issues.

## Pull requests

1. Open an issue first for larger changes, so we can agree on the approach.
2. Keep changes focused; one topic per pull request.
3. Before submitting:
   ```bash
   dart format <changed files>
   flutter analyze
   flutter test
   ```
4. Add or update tests for behavior you change.
5. Code, comments, commit messages and UI texts are in English.

## Hardware

Many features talk to real machines and scales. If you test against real
hardware, never start heating or a shot remotely without making sure the
machine is ready (water in the tank, portafilter in place).

## License

By contributing, you agree that your contributions are licensed under the
[GPL-3.0](LICENSE), the license of this project.
