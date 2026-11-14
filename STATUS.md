# Done First: status

Brief: `../Done First hackathon brief (v2).md`. Question bank: `../dod-examples/`. Flashpoint notes: `docs/flashpoint-notes.md`.
Clock: about 12:30 at last update. Submissions due 3:15, demo 3:30. Karlo relays between Claude Code and Fable Desktop.

## Resume here (after restart)
1. Start Claude Code **from the repo folder**: `cd "/Users/karlok/Project/AI Hackathon Hack the Unreachable/hack-the-unreachable" && claude`. The Flashpoint MCP server is registered for this folder only (local scope).
2. Run `/mcp`, select `flashpoint`, Authenticate, log in, pick the team. Confirm with `claude mcp list` (should no longer say "Needs authentication").
3. Ask Claude to read this file, then run the smoke test (below).

## Decided
- Language: Elixir (1.20.5 / OTP 29). Plain Mix, terminal UI, Req + Jason. Follow `.claude/skills/elixir/SKILL.md`.
- Flashpoint goes behind `DoneFirst.Panel` (cache-first). On a miss it shells out to `claude -p --allowedTools mcp__flashpoint`, so Elixir never signs payments.
- Auth: Claude Code on human OAuth. Docs say OAuth calls are not gated by x402 (subscription covers them). Pending confirmation in the organizers' email.
- Demo path: roguelite, browser game on BabylonJS, sold direct to players. Question bank = `../dod-examples/dod_template.json` (core, 19 sections) + Roguelite entry in `../dod-examples/dod_genre_templates.json` + `priv/templates/web_direct.json`.
- Gap survey: a `grid` question (candidate gaps as rows; columns Not needed / Nice to have / Important / Critical) plus one open `text` question. Flashpoint has no rating type.
- Panels: new `create_and_run` each time (`panel run` on an existing panel is documented as unsupported). Keep panels at 10 to 12 personas.
- Commit and push at each milestone. `.env` holds `ANTHROPIC_API_KEY` (Karlo set it up; never print or commit it).

## Built (all committed and pushed)
- Mix skeleton, Req 0.7.5, Jason 1.4. `mix test` passes (3 tests), compiles with `--warnings-as-errors`.
- `DoneFirst.Claude` (`lib/done_first/claude.ex`): Messages API over Req, `claude-opus-5-5`, `text/3` and `json/4` (JSON-schema outputs), refusal fallbacks on (`fallbacks: "default"`). Live call verified.
- `DoneFirst.Cache` (`lib/done_first/cache.ex`): `fetch(key, fun)` returns `{:ok, value, :cached | :live}`, JSON files under `cache/` (gitignored).
- `DoneFirst.Panel` (`lib/done_first/panel.ex`): `call(key, prompt)` cache-first, `call_live/2` forces a fresh run. Returns Claude Code's JSON envelope (`result`, `total_cost_usd`, `duration_ms`). Not yet run against Flashpoint.
- `DoneFirst.Dotenv`: call `DoneFirst.Dotenv.load()` before using the Claude client.
- `priv/templates/web_direct.json`: 6 sections, 27 items (hosting, browser support, BabylonJS assets, save data, direct sales, launch).

## Next
1. **Smoke test** via `DoneFirst.Panel.call("smoke", prompt)`: ask Claude Code to use Flashpoint `tool_survey` to build a 2-question survey, then `panel` `create_and_run` with 3 personas described as "indie developers who ship browser games built on BabylonJS". Record latency, response shape, and whether the personas read as experts (check the returned `persona` records). Cached to `cache/panel_smoke.json`.
2. **Interview loop**: load core + Roguelite + web_direct. Each turn Claude gets answers so far plus remaining sections, picks the next question or drops sections. Print "dropped N questions: ...".
3. DoD draft + stripping rule (side by side), then panel gap review + single-model baseline, then circle back.

## Open
1. Organizers' email: confirms the OAuth path?
2. Can personas be domain experts? Undocumented; the smoke test answers it.
3. Brief's demo script says "Unity mobile specialists". Fable should reword the routing line and example catch for browser/BabylonJS.
