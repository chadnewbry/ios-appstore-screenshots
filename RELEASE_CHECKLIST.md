# Release Checklist

Use this before broadly promoting `ios-appstore-screenshots`.

## Hard blockers

- [ ] Website template catalog validates cleanly with `npm run validate:templates`
- [ ] Website builds cleanly with `npm run build`
- [ ] CLI builds cleanly with `swift build -c release`
- [ ] `ios-appstore-screenshots generate --template-id <id>` works for every published template ID
- [ ] Homebrew install path works from a clean machine
- [ ] README install instructions match the website install instructions exactly

## CLI release surface

- [ ] Cut a tagged GitHub release
- [ ] Attach release notes with install and upgrade steps
- [ ] Add a changelog or release history policy
- [ ] Add `SECURITY.md`
- [ ] Add `SUPPORT.md`
- [ ] Add `CONTRIBUTING.md`
- [ ] Add at least one automated test target for template install and Maestro parsing behavior

## Website release surface

- [ ] Point the production URL at the final custom domain
- [ ] Confirm Open Graph image, title, and description look correct when shared
- [ ] Confirm every homepage CTA lands on a working install or docs path
- [ ] Review copy for any claims that overstate current functionality
- [ ] Add analytics only if you actually plan to use the data

## Cross-repo checks

- [ ] Verify the CLI default template source still points at the right website repo and branch
- [ ] Verify the current version shown on the website matches the latest CLI release
- [ ] Verify the website comparison table is still accurate against public docs
- [ ] Verify template contribution flow still opens a valid PR against the website repo
- [ ] Test the workflow from a fresh sample app project, not just existing app repos

## Optional next step

- [ ] Decide whether agent workflows should remain repo-local or move into a separate skills repo

Current recommendation: keep skills bundled with the CLI until install, release, and template flows are stable.
