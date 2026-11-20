# Contributing to HerdrDesk

Thanks for helping. Bug reports, small fixes and focused improvements are welcome.

## Before you start

- For anything larger than a small fix, open an issue first so we can agree on the approach.
- HerdrDesk is a companion for [Herdr](https://github.com/herdrdev/herdr-app). Problems in Herdr or Herdr Core belong in their own repositories.

## Development setup

You need macOS 14 or later, Swift 6 and Node.js 22.

```sh
./scripts/build.sh          # builds build/HerdrDesk.app
swift test                  # Swift tests
node --test Tests/*.test.mjs  # web UI tests
```

## Pull requests

- Keep each pull request to one change, and include tests for new behavior or the bug you fixed.
- Run both test suites before you open the pull request, and say in the description how you checked the change.
- UI text exists in English, Korean and Japanese (`Resources/web/locale.js`). Add all three when you add a string. If you can't translate, add English and say so in the pull request.
- Use only synthetic data in tests, screenshots and examples. Never include real terminal output, conversation history, team names, hostnames, paths or credentials.
- Do not commit build output (`build/`, `.build/`, `Resources/web/bundle.js`).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
