# Contributing to Halo

Thanks for contributing. Small, focused pull requests are easiest to review.

## Before opening a pull request

1. Open an issue first for substantial changes so the direction can be discussed. Use [Discussions](https://github.com/zeiprone/Halo/discussions) for setup questions, ideas, and showcases rather than opening a support issue.
2. Keep the app’s privacy model intact: do not add telemetry, account systems, audio uploads, or remote control without explicit discussion.
3. Run `swift test` and, for UI changes, `./script/build_and_run.sh --render-check`.
4. Update user-facing documentation when behavior, permissions, or requirements change.

## Code guidelines

- Keep `HaloCore` platform logic testable and independent from SwiftUI where practical.
- Use Swift concurrency safely; do not move real-time audio work onto the main actor.
- Avoid unrelated reformatting or generated files in a pull request.
- Preserve accessibility labels and macOS permission messaging when modifying UI or integrations.

## Commit and pull request guidance

Use a concise, imperative title. In the pull request description, state what changed, how you tested it, and any behavior or permission changes users should know about.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).

## Finding a place to help

- Start with issues labelled [`good first issue`](https://github.com/zeiprone/Halo/labels/good%20first%20issue), or look for [`help wanted`](https://github.com/zeiprone/Halo/labels/help%20wanted).
- The repository uses `area: player`, `area: lyrics`, `area: visuals`, and `area: docs` to make scope clear.
- Read the [roadmap](ROADMAP.md) for current directions. It is an intent list, not a promise or a substitute for discussing a substantial change first.
