# Done First: status

Brief: `../Done First hackathon brief (v2).md`. Question bank: `../dod-examples/`.

## Decided
- Language: Elixir (1.20.5 / OTP 29 installed). Plain `mix new`, terminal UI, Req + Jason.
- Follow `.claude/skills/elixir/SKILL.md`.
- Flashpoint goes behind one cache-first module (`DoneFirst.Panel`). On a cache miss it shells out to headless Claude Code (`claude -p` with Flashpoint MCP), so Elixir never signs x402 payments. Swap to direct MCP over Req later if auth allows.

## Checked
- `dod_template.json` (19 sections), genre and platform templates all load.
- Repo is fresh, remote `karlok/hack-the-unreachable`.

## Open questions (waiting on Karlo)
1. Auth path from mentor: human OAuth or funded wallet? Correct MCP endpoint?
2. Flashpoint smoke test done yet?
3. Fetch docs.flashpoint.ai now (panel, create_and_run, auth, expert personas)?
4. Question bank: core + Roguelite + iOS or Google Play?
5. Anthropic key: is it in `../creds.md`? Karlo pastes into `.env`, or Claude copies it?
6. Fable handoff style: this STATUS.md, or specs from Fable?
7. Current time, demo still 3:30?
8. OK to commit and push at milestones?

## Next
Once 1, 2, 5 are answered: Mix skeleton, Claude client, cached Panel module (~20 min).
