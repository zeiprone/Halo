# Contributing to Halo

Thanks for contributing. Small, focused pull requests are easiest to review.

## Before opening a pull request

1. Open an issue first for substantial changes so the direction can be discussed.
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
