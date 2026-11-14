# Done First

Done First helps a builder write a definition of done (DoD) and then has a panel of practitioners find what it is missing, without showing the panel the idea.

Built for the Flashpoint.AI "Hack the Unreachable" hackathon, **Self-Improving AI** track: the agent drafts a scope, recognizes that it cannot judge its own completeness, routes the question to the people who can, and folds their answers back in.

The worked example is an indie game (a browser roguelite on BabylonJS, sold direct from the developer's site). The question bank is a swappable file, so the same loop works for a freelance or RFP scope template.

## How it works

| Step | Mix task | What happens |
| --- | --- | --- |
| 1. Interview | `mix done_first.interview` | Claude asks 2 to 3 questions per turn and drops sections and items the answers make irrelevant. Bank: 28 sections, 286 items. |
| 2. Draft and strip | `mix done_first.draft` | Claude writes 25 to 40 tailored DoD items, each with a stripped twin for the panel. A code check confirms no removed term reaches the panel. |
| 3. Panel review | `mix done_first.review` | Claude picks who should review the DoD and prints the routing line. Flashpoint builds a survey, runs a synthetic panel through it, and returns every response row. |
| 4. Baseline | `mix done_first.baseline` | A single model answers the same survey, as a control. |
| 5. Circle back | `mix done_first.circle_back` | The panel's open answers are grouped into catches and checked against the DoD. The builder is asked only about the real gaps, and the final DoD lands with a trail. |

**Stripping rule.** Nouns, names, story and specific mechanics come out; constraints, interfaces, formats and budgets stay in. Genre, engine and platform go to the panel on purpose, because the panel needs them to judge completeness. The title, setting, art style, story and price never leave. The leak check is a whole-word scan of the stripped text for every removed term and the title. It proves those words do not reach the panel; it does not prove the idea cannot be guessed from structure.

## Requirements

- Elixir 1.20 / OTP 29.
- [Claude Code](https://claude.com/claude-code) with the Flashpoint MCP server added for this folder and signed in:
  ```sh
  claude mcp add --transport http flashpoint https://api.flashpoint.ai/mcp
  ```
  Then run `/mcp` inside Claude Code, pick `flashpoint`, and authenticate. Flashpoint calls go through headless Claude Code (`claude -p`) on your own sign-in, so this project never signs payments.
- An Anthropic API key in `.env` as `ANTHROPIC_API_KEY` (optional). Without one, or if the key hits a spend limit, the Claude client falls back to `claude -p`, which is about 3 times slower. Set `DONE_FIRST_BACKEND=cli` to force that path.
- The question bank is included: core and genre templates in `priv/bank/`, the platform template in `priv/templates/web_direct.json`.

## Running it

```sh
mix deps.get
mix test

# A simulated builder answers from a fact sheet. Drop --facts to answer yourself.
mix done_first.interview --facts priv/demo/roguelite_facts.md
mix done_first.draft --notes priv/demo/roguelite_facts.md
mix done_first.review --size 12
mix done_first.baseline
mix done_first.circle_back --facts priv/demo/roguelite_facts.md
```

Every step caches to `cache/` and replays by default, so a demo never waits on a live call. Pass `--fresh` to regenerate a step. If a panel run is interrupted, resume it from its ids:

```sh
mix done_first.review --survey-id S --panel-id P --run-id R
```

## Sample output

From one run with 12 panelists. Trimmed.

Interview:
```
Q2: Does the game have any online features (multiplayer, leaderboards, accounts), and how will you make money?
A: No online stuff at all. It's single-player only... It's paid up front from my website through Stripe or Paddle.
  -> dropped 36 questions: Multiplayer & Online Features (11), Platform, Technical & Legal (6), Localization & Text Completeness (5), ...
Done after 9 questions. Kept 228 items in 27 sections, dropped 58.
```

Draft and strip:
```
DRAFT (builder sees)                   | STRIPPED (panel sees)
---------------------------------------+---------------------------------------
$8 one-time price configured in the    | Single low-price one-time purchase
chosen provider, currency display      | configured in the chosen provider,
decided, and a real live-mode purchase | currency display decided, and a real
completed and refunded end to end.     | live-mode purchase completed and
                                       | refunded end to end.

What left: top-down, caverns, cavern, Pixel-art style, low-poly, $8, lore notes, ending text screen, from a friend, depth
Leak check (by code): 0 removed terms reach the panel.
```

Panel review:
```
routing to: Solo devs selling BabylonJS browser roguelites direct (12)
12 responses.
- [Solo Game Developer and Web Graphics Engineer] Missing the ugly edge cases around save integrity and
  entitlement recovery: versioned migrations, conflict handling between tabs/devices, and a tested re-unlock
  path if browser data is cleared or the cached build gets stale...
```

Circle back:
```
What the panel caught (5 new, raised unprompted):
  [5/12] Corrupted save recovery and save backup (NEW, raised unprompted, single model missed it)
  [4/12] Rollback plan for a bad deploy (NEW, raised unprompted, single model also raised it)
  [2/12] Storage blocked, full or persistence denied (NEW, raised unprompted, single model missed it)
  [2/12] Payment webhook failure or interrupted purchase (NEW, raised unprompted, single model missed it)
  [1/12] Browser back-button behavior (NEW, raised unprompted, single model missed it)
  [8/12] Save conflicts between tabs or devices (echoes a rated candidate)
  ...
  [3/12] Support path for payment and unlock issues (already in draft)

Added to the definition of done:
  - [ ] Done when the previous build is kept deployable and a written rollback procedure has been rehearsed
        once on production hosting, restoring the prior version within a stated target time.
  ...
```

The final DoD is written to `cache/final_dod.md`.

## Labels in the trail

Catch labels are computed in code by exact text match, not by the model:

- **NEW, raised unprompted**: in neither the draft nor the survey rows the panel rated.
- **echoes a rated candidate**: repeats a row the panel was shown in the grid, so it was prompted.
- **already in draft**: the builder's draft already covered it.

The single-model comparison is shown only on NEW catches, because the single model saw the candidate rows too.

## Known limitations

- **The panel is synthetic.** Flashpoint generates the personas from the research objective, and a different model family answers (gpt-5.4-mini, uncalibrated). The personas read as practitioners (shipping history, payment providers, browser bugs they have fought), but they are not real people.
- **The severity grid straightlined.** In the sample run every panelist rated every candidate gap Critical, so the grid does not rank anything. The open-ended answers carry the signal. A forced-choice question (rank or pick the top 3) is the likely fix.
- **The baseline is not beaten outright.** The single model rated the grid with more spread, and its own list found things the panel did not (audio autoplay rules, email deliverability, non-QWERTY layouts). What the panel adds is 12 independent voices whose repeats show priority, from a different model family.
- **Flashpoint latency varies.** One `tool_survey` call hung for 328 s and hit Claude Code's MCP timeout even though the survey had been created. The review step therefore runs in two resumable stages and refuses to save a run with no responses.

## Layout

```
lib/done_first/claude.ex        Messages API client, with the claude -p fallback
lib/done_first/panel.ex         Cache-first door to Flashpoint through headless Claude Code
lib/done_first/cache.ex         JSON disk cache
lib/done_first/bank.ex          Loads and flattens the question bank
lib/done_first/interview.ex     Interview core (pure)
lib/done_first/draft.ex         Draft, stripping rule, leak check (pure)
lib/done_first/review.ex        Routing, survey prompts, tally (pure)
lib/done_first/circle_back.ex   Catch triage, labels, final DoD (pure)
lib/mix/tasks/                  One Mix task per step
priv/bank/                      Core DoD and genre templates (question bank)
priv/templates/web_direct.json  Platform template: browser game sold direct
priv/demo/roguelite_facts.md    Fact sheet for the simulated builder
```

## License

MIT
