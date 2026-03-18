# Contributing

## Development

```bash
swift build
swift test
```

Release build:

```bash
swift build -c release
```

## Before opening a PR

- keep changes scoped to one problem
- update docs when behavior or install flow changes
- run `swift test`
- run `swift build -c release`

## Areas that need extra care

- CLI argument behavior
- template schema compatibility with `ios-appstore-screenshots-website`
- Maestro execution and screenshot file movement
- GitHub submission flow

## Template compatibility

The CLI depends on template data published from the website repo. If you change template installation behavior or schema assumptions here, update the website repo in lockstep.
