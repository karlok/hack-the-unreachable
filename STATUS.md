# Done First: status

Brief: `../Done First hackathon brief (v2).md`. Question bank: `../dod-examples/`. Flashpoint notes: `docs/flashpoint-notes.md`.
Clock: about noon, demo 3:30, submissions due 3:15. Karlo relays between Claude Code and Fable Desktop.

## Decided
- Language: Elixir (1.20.5 / OTP 29). Plain `mix new`, terminal UI, Req + Jason. Follow `.claude/skills/elixir/SKILL.md`.
- Flashpoint goes behind one cache-first module (`DoneFirst.Panel`). On a cache miss it shells out to headless Claude Code (`claude -p` with the Flashpoint MCP).
- Auth (pending the organizers' email): Claude Code on human OAuth. Docs say OAuth calls are not gated by x402, so no wallet signing in our code.
- Demo path: roguelite, browser game on BabylonJS, sold direct to players. Question bank = `dod_template.json` + Roguelite genre + a new `web_direct` platform template (none of the 7 existing platforms fits; Itch.io is the closest).
- Gap survey: a `grid` question (gaps as rows, severity as columns) plus one `text` question. Flashpoint has no rating type.
- Commit and push at each milestone. Karlo sets up `.env`. `.gitignore` already covers `.env`, `.env.*`, `/cache/`.

## Checked
- Templates load: core (19 sections), genres, 7 platforms.
- Flashpoint docs reachable and summarized in `docs/flashpoint-notes.md`.

## Open
1. Organizers' email: confirms the OAuth path?
2. Smoke test not run yet. Karlo: `! claude mcp add --transport http flashpoint https://api.flashpoint.ai/mcp`, then `/mcp` to log in and pick a team.
3. Can personas be experts ("BabylonJS web game developers")? Undocumented. The smoke test answers it.
4. `panel run` on an existing panel: docs say unsupported, llms.txt lists it. Plan on `create_and_run` each time.

## Next
1. Smoke test: a 2-question survey on a 3-persona panel. Record latency, response shape, persona realism. Save to `cache/`.
2. Meanwhile: Mix skeleton, `web_direct` platform template, Claude client, cached `DoneFirst.Panel`.
