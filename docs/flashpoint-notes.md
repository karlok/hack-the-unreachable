# Flashpoint notes

Read from docs.flashpoint.ai, docs.flashpoint.ai/llms-full.txt and flashpoint.ai/llms.txt on 2026-11-14.

## Endpoint and hookup
- Production: `https://api.flashpoint.ai/mcp` (Streamable HTTP, JSON-RPC `tools/call`). Staging: `https://mcp-staging.flashpoint.ai/mcp`.
- `claude mcp add --transport http flashpoint https://api.flashpoint.ai/mcp`. On first tool use a browser opens for login and a team pick.

## Auth and who pays
- **Human OAuth (Claude Code / Desktop):** "Human bearers (Auth0 or OAuth) are not gated by x402; your subscription covers per-call usage." Token is a 24h JWT bound to user and team, no refresh token, re-OAuth when it expires.
- **Wallet agents:** challenge, EIP-191 sign, 1h wallet JWT, then x402 per paid call (402, sign EIP-3009, retry with `X-PAYMENT`). Payer must match the JWT wallet. Failed calls are not settled.
- No page says Claude Code can sign x402 itself. The OAuth path avoids the question entirely.

## Tools
- `tool_survey`: `brief` (required), `survey_id`, `conversation_id`. Returns `{conversation_id, survey_id, ...}`. 60 to 600 s. Publish, delete, email and paid recruitment need a second "confirm" call on the same `conversation_id`.
- `panel`:
  - `create`: `name`, `num_respondents` (1 to 200), `research_objective`. Returns `panel_id`.
  - `create_and_run`: the above plus `survey_id`. Returns `panel_id` and the run result. Streams progress.
  - `run`: docs say NOT supported on the direct path (personas live in the orchestrator). llms.txt lists it at $0.10. Assume create_and_run each time, or ask `chat` to rerun a panel by id.
  - `recruit`: real people, needs a mentor check. Do not use.
  - Optional: `context` (string), `audience` (object, no schema documented).
- `demographics`: `location` (required), `question`, `audience`.
- `chat`: `message`, `conversation_id`. Returns `{conversation_id, reply}`.
- Others: `presentation`, `payment_confirmation` (wallet only).
- Result shape for panel/demographics: `{status, result, error, timing}`. Synthetic response rows: `data` like `{"Q1": "1", "Q2": "3"}`, `persona`, `status`, `panel_id`.

## Personas
- No profession or expert field is documented. Personas come from the free-text `research_objective` (plus `context`, `audience`). The platform fills in demographics (including occupation), psychographics, behaviors and survey traits.
- "BabylonJS web game developer" as a persona is undocumented. Test it in the smoke test and check the returned `persona` records.

## Question types (relevant ones)
- No rating or Likert type. For the gap survey use a `grid`: rows are candidate gaps, columns are severity labels (e.g. Not needed / Nice to have / Important / Critical).
- Open text: `text`.
- Also available: `select` (single/multi), `nps`, `ranking`, `maxdiff`.

## Prices (wallet path only; OAuth is covered by subscription)
chat $0.01, demographics $0.05, presentation $0.25, tool_survey $0.50, panel create $0.50, create_and_run $0.60, recruit $0.50 plus provider.

## Latency
tool_survey 60 to 600 s. Synthetic panels: personas in seconds, responses in minutes. create_and_run can run long (docs mention ~45 min for big runs). Keep panels small (10 to 12).

Contact: developers@flashpoint.ai
