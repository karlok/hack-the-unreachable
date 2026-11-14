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

## Smoke test results (done)
- Flashpoint over OAuth works through `DoneFirst.Panel`. Cached: `cache/panel_smoke.json`, `cache/panel_smoke_answers.json`.
- Server time: tool_survey about 18 s, create_and_run about 19 s (personas 16 s, responses 3 s). Whole headless run about 106 s and $0.48 of Claude Code tokens. Fetching answers: about 55 s, $0.30.
- create_and_run returns a job id and must be polled. Its result has NO answers, only counts. Get rows with a second `tool_survey` call (survey_id + brief naming panel_id and run_id). Answers come keyed Q1, Q2.
- Use the panel id from `artifact_id` (it matches `analytics_scope.panel_id`), not the top-level `panel_id`. Three different ids appear.
- Personas CAN read as experts: occupation "Independent Browser Game Developer", custom_attributes `primary_game_engine: BabylonJS`. Rest is consumer-style. Responses from gpt-5.4-mini, uncalibrated.
- Answers were on point: all 3 flagged mobile touch / Safari testing; one flagged CDN cache headers and a rollback plan.

## Next
1. ~~Smoke test~~ done.
2. **Interview loop**: done and run live. `mix done_first.interview [--facts priv/demo/roguelite_facts.md]` (no --facts = you answer). Bank = 28 sections, 286 items. Batches 2 to 3 questions per call; drops whole sections and single items; prints "dropped N questions: Section (n), ...". Last run: 9 questions, 58 dropped, 37 s on the API. Result in `cache/interview_last.json` (the DoD draft step reads this).
3. **DoD draft + stripping rule**: done. `mix done_first.draft [--notes priv/demo/roguelite_facts.md] [--fresh]` reads `cache/interview_last.json`, writes 25 to 40 tailored items each with a stripped twin, prints them side by side, prints "What left", and runs a code leak check (allowlist for technical phrases like "depth sorting"). Saves `cache/dod_draft.json` with `panel_view` (27 section headings + 32 stripped items) for the gap review. Rerun replays the file; `--fresh` regenerates (about 60 s).
   - Edge cases decided: interfaces/providers stay (Stripe, Gamepad API, BabylonJS); "caverns" becomes "levels"; "$8" becomes "single low-price purchase" (Karlo can flip this).
   - On stage say "zero removed terms reach the panel, checked by code". Do not say "theft-proof": the scan cannot prove the idea is unguessable from structure.
   - Demo: lead with which whole sections dropped (Multiplayer, etc.), not the percentage (only about 16 to 20% of items drop).
4. **Next: panel gap review** from `panel_view` (routing line, grid survey, parse), then single-model baseline, then circle back.

## Open
1. Organizers' email: confirms the OAuth path?
2. Can personas be domain experts? Undocumented; the smoke test answers it.
3. Brief's demo script says "Unity mobile specialists". Fable should reword the routing line and example catch for browser/BabylonJS.
4. ~~API key spend limit~~ resolved: hosts gave a new key (in `.env`). `DoneFirst.Claude` still falls back to `claude -p` automatically on a spend-limit 429 or missing key, or always with `DONE_FIRST_BACKEND=cli` (about 3x slower).
