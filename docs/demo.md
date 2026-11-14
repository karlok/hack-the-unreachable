# Demo run sheet

Run sheet for the 3:30 demo. Fable's script supplies the words; this file supplies the commands, what to point at, and the timing. Every step below replays from `cache/` in under a second, so nothing on stage waits on a live call except the optional kickoff in step 0.

## Before you go on

1. Open two terminals in the repo folder, each at least 80 columns wide (the draft's side-by-side table needs 80).
2. Confirm the cache is present: `ls cache/interview_last.json cache/dod_draft.json cache/review.json cache/baseline.json cache/final_dod.json`. All five must exist.
3. Dry run every command in steps 1 to 5 once, in order. Each should print `Replaying ...` or finish instantly.
4. Clear both terminals (`clear`). Bump the font size so the back row can read it.
5. Optional: open `cache/final_dod.md` in an editor tab for the closing shot.

Do NOT run any step with `--fresh` on stage except the kickoff below, which writes to its own file.

## 0. Live kickoff (terminal 2, first 10 seconds, optional)

```sh
mix done_first.review --fresh --size 12 --out cache/review_live.json
```

- Shows: the routing line, then "building the gap survey and running the panel".
- Why: proves the Flashpoint call is real while you narrate the cached run in terminal 1.
- Safe: it writes to `cache/review_live.json`, so the cached run the rest of the demo uses is untouched.
- Timing: 3 to 10 minutes, and it can stall (see "If something goes wrong"). Do not wait on it. If it finishes before you close, point at it; if not, never mention it again.

## 1. Interview (terminal 1)

```sh
mix done_first.interview --facts priv/demo/roguelite_facts.md
```

- Shows: 9 questions in 3 batches, a simulated builder's answers, and a `-> dropped N questions: ...` line after each batch. Ends with "Kept 228 items in 27 sections, dropped 58."
- Point at: the first drop line, `dropped 36 questions: Multiplayer & Online Features (11), ...`. Lead with which whole sections went, not the percentage (only about 20% of items drop).
- Note: a replay prints everything at once, so scroll back up to Q1 and walk down.

## 2. Draft and strip (terminal 1)

```sh
clear && mix done_first.draft
```

- Shows: the stripping rule, the DRAFT | STRIPPED table, a "What left:" line, and the leak check.
- Point at: the `$8 one-time price` row becoming `Single low-price one-time purchase`, then the "What left" line, then `Leak check (by code): 0 removed terms reach the panel.`
- Say it this way: "Zero removed terms reach the panel, checked by code." Do not say "theft-proof": the scan proves the words do not leave, not that the idea cannot be guessed.
- Pre-empt the obvious question: "Genre, engine and platform go to the panel on purpose. The title, setting, art style, story and price never leave."

## 3. Panel review (terminal 1)

```sh
clear && mix done_first.review
```

- Shows: `routing to: Solo devs selling BabylonJS browser roguelites direct (12)`, the occupations, the grid table, then the panel's open answers.
- Point at: the routing line first (the agent chose who to ask from what it learned), then two or three open answers. Good ones: the Web Graphics Engineer ("the ugly edge cases around save integrity and entitlement recovery...") and the Retired Software Tester ("two open tabs or a stale restore can overwrite newer progress...").
- Skip: the grid table. Every panelist rated every row Critical, so it ranks nothing. If asked, say so plainly: synthetic panels straightline on a 4-point grid, and the open answers carry the signal.

## 4. Baseline (terminal 1, optional, 15 seconds)

```sh
clear && mix done_first.baseline
```

- Shows: the panel's counts next to a single model's ratings, then the single model's own "what else is missing".
- Use only if the script has room or a judge asks "why not just ask Claude?". The honest answer: the single model is useful and found different things (audio autoplay, email deliverability). The panel adds 12 independent voices from a different model family (gpt-5.4-mini), and their repeats show priority.

## 5. Circle back (terminal 1, the payoff)

```sh
clear && mix done_first.circle_back
```

- Shows: "What the panel caught (5 new, raised unprompted)", the trail, the 5 questions sent back to the builder, and the 9 items added to the DoD.
- Point at: the top line, `[5/12] Corrupted save recovery and save backup (NEW, raised unprompted, single model missed it)`, then `[4/12] Rollback plan for a bad deploy`.
- The line that holds up: "The panel raised 5 things unprompted that were in neither the draft nor the survey. The single model's own list caught 1 of them."
- Then: "The builder only answers these 5, not the whole checklist again." Point at one added item, such as the rollback rehearsal.
- Close on: `cache/final_dod.md` in the editor, trail at the top.

## Timing

| Step | On screen | Talk time |
| --- | --- | --- |
| 0. Kickoff | instant | 10 s |
| 1. Interview | instant | 40 s |
| 2. Draft and strip | instant | 40 s |
| 3. Panel review | instant | 45 s |
| 4. Baseline | instant | 0 to 15 s |
| 5. Circle back | instant | 45 s |

About 3 minutes without the baseline.

## If something goes wrong

- **A command recompiles or prints warnings first.** Harmless; run it again and it will be instant.
- **A step prints "... drafting" or "... choosing next questions" and waits.** It is making a live call, which means its cache file is missing. Ctrl-C and move on to the next step; every later step reads its own saved file.
- **The kickoff stalls at "Generating personas" or a survey call hangs.** Known Flashpoint behavior (one call hung 328 s in testing). Ignore it. If it errors with "The panel run did not finish", that is the guard working: nothing was saved over the cached run.
- **The Anthropic API key fails.** The client falls back to `claude -p` on its own. Replays do not call the API at all.
- **Total failure.** `cache/final_dod.md` is the whole story in one file: trail first, then the DoD.

## Numbers to have ready

- Bank: 28 sections, 286 items. Interview: 9 questions, 58 dropped, 228 kept.
- Draft: 32 tailored items, 10 terms removed, 0 leaks.
- Panel: 12 synthetic practitioners on Flashpoint, about 1 minute of server time for 12 responses.
- Catches: 12 total, 5 new and unprompted, 6 echo the rated rows, 1 already in the draft. 9 DoD items added.
