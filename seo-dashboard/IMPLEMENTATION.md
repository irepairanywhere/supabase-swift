# Launchpad SEO — Architecture Audit & Implementation Plan

**Audited:** 2026-08-24 · **Auditor role:** senior product engineer / SEO analytics architect
**Scope rule:** everything below is verified against what actually exists. Nothing is invented.

---

## 0. The most important finding first

**There is no application codebase.** This git repository is the Supabase Swift SDK
(`supabase-swift`, a Swift package — `Package.swift`, `Sources/`, `Tests/`); it contains zero
dashboard code (verified by search: no references to the dashboard, DataForSEO, or Search
Console anywhere in the tree). The branch `claude/seo-ai-dashboard-lscekk` was provisioned as a
home for this work, which is why this document lives here.

The product called "Launchpad SEO" is:

- **One static HTML artifact** published to Claude Artifacts at
  `https://claude.ai/code/artifact/963f3140-a8fb-4d97-8e51-70df45eaaed9` (versions:
  `v1-rocketlaunchmedia`, `v2-semrush-parity`, `v3-real-gsc-ga4`).
- **Source files in ephemeral session scratchpad** (not in git, lost when the session
  container is reclaimed):
  - `dashboard_template.html` (~42 KB) — full page: markup, CSS, JS, hardcoded data arrays,
    plus two placeholders `__KW_DATA__` / `__GAP_DATA__`.
  - `keywords.json` (100 rows), `gap.json` (25 rows) — extracted API pulls injected at build.
  - `launchpad-seo.html` — built output (verified: no leftover placeholders).
- **A conversation-time data pipeline**: Claude calls MCP tools, condenses responses with
  throwaway Python, injects/hand-transcribes numbers into the template, republishes.

Everything else in this document describes that system honestly and plans from it.

---

## 1. Current architecture

| Concern | Reality |
|---|---|
| Framework | None. Single-file vanilla HTML/CSS/JS. No build toolchain beyond a 5-line Python string-replace. |
| Routing | JS tab switcher (`setTab()`), 8 panels, selected tab persisted to `localStorage("lp-tab")` in try/catch. |
| Components | Hand-rolled: KPI cards, SVG line charts (`lineChart()`), CSS bar lists (`barList()`), paired new/lost bars, keyword cards, tables. |
| Styling | Inline `<style>`; CSS custom properties; three-state theming (bare `:root` light, `prefers-color-scheme: dark` guarded `:not([data-theme="light"])`, explicit `[data-theme="dark"]`); fonts: Barlow / Barlow Semi Condensed / IBM Plex Mono via Google Fonts (the only external host the Artifact CSP allows). |
| Database | None. No persistence of any kind beyond `localStorage` (tab selection only). |
| Authentication | None in-page. Access control = Artifact link privacy (private by default; user-controlled sharing). |
| Deployment | Republish same file path via the Artifact tool → same URL, new version label. |
| Scheduled jobs | None exist. No refresh Routine has been created. |
| Caching / API routes / env vars / server error handling | None — there is no server. The page makes zero network requests at runtime (CSP forbids them anyway). |

### Integrations (all conversation-time, none runtime)

| Integration | Status | How it's used |
|---|---|---|
| DataForSEO MCP | Used | Labs (rank overview, historical, ranked keywords, relevant pages, competitors, domain intersection), Backlinks (summary, timeseries, anchors, referring domains), AI Optimization (LLM mentions agg/top-domains, AI keyword volume, live `llm_response` on `gpt-5.5` and `sonar-pro`). |
| Composio → Google Search Console | ACTIVE, used | Account `google_search_console_piki-marcan`; property `https://rocketlaunchmedia.com/` (siteOwner). ~24 properties visible incl. client sites. |
| Composio → GA4 | ACTIVE, used | Account `google_analytics_myitis-cusk`; live property `properties/450800768` ("rocketlaunchmedia.com"); `properties/317880329` ("rocketlaunch media - GA4") verified empty. |
| WordPress MCP servers | Present in session, **not used by the dashboard** | `rocketlaunchmedia_mcp`, `JNIMMIGRATION_COM_MCP`, `exterior_alliance` — read *and write* tools (create/update/delete posts, SEO meta). No dashboard data flows from or to them today. |
| AI answer testing | Used | Via DataForSEO `ai_optimization_llm_response`, single-run per model, one prompt phrasing, `web_search: true`. |

---

## 2. Data-flow map

```
DataForSEO MCP ──┐  (labs / backlinks / AI-opt pulls, Aug 23–24 2026)
                 ├─► oversized responses land in session tool-result files
Composio MCP ────┤  (GSC + GA4 pulls, Aug 24 2026; big payloads land in
 (GSC, GA4)      │   Composio sandbox /mnt/files/mex/*.json)
                 ▼
     throwaway Python extraction (session shell / Composio workbench)
                 ▼
   keywords.json, gap.json ──(string-replace into __KW_DATA__/__GAP_DATA__)──┐
   everything else ──(hand-transcribed by Claude into JS const literals)─────┤
                 ▼                                                           │
        dashboard_template.html  ──build──►  launchpad-seo.html ◄────────────┘
                 ▼
   Playwright render check (390px, light+dark) ──► Artifact publish (same URL)
```

**No arrow is automated.** Every refresh is Claude re-running this by hand in a conversation.
The hand-transcription step is the weakest link: ~15 JS arrays (`TREND`, `GSCM`, `GA4M`,
`CHAN`, `GSCQ`, `GSCP`, `DEV`, `DIST`, `COMP`, `PAGES`, `LINKMO`, `ANCHORS`, `REFDOMS`,
`AISRC`, `AIVOL`) are typed from tool output, with no schema check between source and page.

---

## 3. Metric definitions (what each shown number actually is)

| Surface | Metric | Class | Definition / source |
|---|---|---|---|
| Overview | Ranking keywords 91 | snapshot | DataForSEO historical rank overview, Aug 2026 row. |
| Overview | Est. clicks 26 / traffic value $567 | **estimate** | DataForSEO ETV: position × volume × CTR-curve model; $ = equivalent Google Ads cost, **not revenue**. |
| Overview | Trend charts | snapshot series | Historical rank overview, Mar–Aug 2026 (6 monthly rows; that is all the API returned). |
| Overview | Movement chips (new 40 / up 16 / down 31 / lost 97) | snapshot | Per-DataForSEO-database-update deltas, **not** calendar month-over-month. |
| Traffic | GSC clicks/impressions/position | **measured, snapshot** | GSC API, daily rows aggregated to months in Python; position = impression-weighted mean. Aug = **month-to-date through Aug 21** (GSC data lag). |
| Traffic | CTR 0.04% | derived | 66 clicks ÷ 158,368 impressions pooled over May 24–Aug 21 (correct pooled method, not row-averaged). |
| Traffic | GA4 sessions / channels / AI Assistant 17 | **measured, snapshot** | GA4 Data API, property 450800768. Aug = MTD through Aug 23. "AI Assistant" is GA4's own channel-group definition. |
| Keywords | 100 keyword cards | snapshot | `ranked_keywords` pull, Aug 23. 100 unique keywords (verified). Movement badges = that pull's `rank_changes`, a **different update cycle** than the Overview chips. |
| Pages / Competitors / Gap | all values | snapshot / estimate | Labs endpoints; competitor "Type" labels (Agency/Directory/Tool site) are **hand-written editorial classifications**. |
| Backlinks | 692 / 140 / rank 234 / spam 3 | snapshot | Backlinks summary. **Dofollow 442 is computed** as 678 referring pages − 236 nofollow pages — a pages-basis number presented next to a links-basis total (692); mild basis mismatch. |
| Backlinks | New-vs-lost 13-month bars | snapshot series | Crawler first-seen/lost dates, not true acquisition dates. |
| AI Visibility | ChatGPT mentions 6 / volume 58 | snapshot | DataForSEO LLM-mentions DB — a **sampled prompt corpus**, not a census. |
| AI Visibility | Google AI Overviews 0 | snapshot, bounded claim | `ranked_keywords` with `item_types:["ai_overview_reference"]` returned zero rows — "no citations found on tracked keywords", not proof of universal absence. |
| AI Visibility | "Not cited" live test | **single-run experiment** | One prompt, one run per model (gpt-5.5, sonar-pro), Aug 24. LLM outputs are non-deterministic. |
| AI Visibility | AI prompt volumes ("~1", "~2") | estimate, hand-rounded | DataForSEO AI keyword volume; tildes are editorial. |
| Everywhere | Analyst notes | editorial | Claude-written interpretation, frozen at publish time. |

**Nothing on the page is live.** Every number is baked at build time.

---

## 4. Problems found

### Correctness / potentially misleading
1. **MTD vs full-month comparisons.** KPI cards compare Aug MTD (16 clicks through Aug 21 ≈ 68%
   of the month) against full months ("peaked at 88 in March"). Disclosed only in the Traffic
   tab's intro line; Overview's "▼ 77%" mixes an estimate series with no MTD note at all.
2. **Three different "keyword count" truths.** Domain overview said 92; historical Aug row says
   91 (used in KPI + DIST, which sums to 91 ✓); the Keywords tab embeds 100 keywords from a
   third pull. No provenance labels distinguish them.
3. **Movement double-vision.** Overview chips and per-keyword badges come from different pulls
   with different baselines; a keyword can look "new" in one and absent in the other.
4. **"Lost 97" chip** reads like August churn; it's the DataForSEO update-cycle `is_lost`
   counter, correlated with but not equal to monthly loss.
5. **Traffic value $567** invites revenue misreading; it is Ads-replacement cost of *estimated*
   clicks (~2× the real GSC click level).
6. **Backlink velocity narrative.** "3rd positive month" counts include one client-site footer
   deployment (Nov spike = 147 links, largely one domain) and 100+ nofollow listing links;
   dofollow figure has the basis mismatch noted above.
7. **AI metrics overstated certainty.** Single-run LLM tests, sampled mentions DB, and a
   "0 AI Overviews" claim bounded by the tracked-keyword set are presented with more confidence
   than the sources warrant (partially mitigated by footer text).
8. **Fragility:** hand-transcribed arrays have no reconciliation checks; nothing prevents a
   typo'd number from shipping.

### Mobile layout
9. Tables keep `min-width: 520px` inside `overflow-x:auto` — usable but scroll-to-read on
   phones; keyword-card layout is the better pattern and isn't used for GSC/anchor tables.
10. 8-tab nav scrolls horizontally with **no visual affordance** (scrollbar hidden, no fade/
    chevron) — "AI Visibility" is invisible off-screen on 390px until the user guesses to swipe.
11. Chart tooltips are SVG `<title>` — hover-only, effectively **no tooltips on touch**.
12. 12-point line charts crowd x-labels at 390px (readable, but at the limit).

### Security / data handling
13. **Credentials: sound.** No secrets in the page or repo; DataForSEO auth lives server-side
    in the MCP; Google OAuth lives in Composio. The page makes no runtime requests.
14. **Artifact contents are shareable business intelligence**: client identities (referring
    client domains), founder name, phone number, spam-link problems, traffic decline. One
    forwarded link exposes all of it. Acceptable for an internal tool; must be re-evaluated
    per-client if client-facing dashboards are made.
15. **Tenant separation is manual.** The Composio Google connections expose ~24 properties
    (agency + clients). Nothing structural prevents a future refresh from mixing client A's
    data into client B's page except operator care. Multi-client work needs one artifact per
    client and a per-client config that whitelists exactly which properties may be read.
16. **WordPress MCP write tools** (post/page/meta create-update-delete on three client sites)
    are present in the same session. The dashboard never calls them; keep that invariant —
    dashboard refreshes must be read-only by policy.
17. **Single point of loss:** source + data files live only in session scratchpad. A reclaimed
    container orphans the published artifact (no way to rebuild or diff it). This is the most
    urgent operational risk.

---

## 5. Recommended database changes

There is no database, and this stage doesn't need one. Recommended, in order of leverage:

1. **Git-as-time-series (now).** Commit to this branch under `seo-dashboard/`:
   `dashboard_template.html`, `build.py`, and `snapshots/<domain>/<YYYY-MM-DD>/*.json`
   (raw condensed pulls: keywords, gap, gsc_monthly, ga4_monthly, backlinks, ai). Each refresh
   adds a dated snapshot dir. This fixes problem 17 and creates real history for trends —
   including the rank-tracking history DataForSEO can't give us (its history maxed out at 6
   months here).
2. **Later, if multi-client + shared access is wanted:** a real store (Supabase Postgres is the
   natural fit given the team context): tables ~ `clients`, `snapshots`, `keyword_ranks`,
   `gsc_daily`, `backlink_events`, `ai_tests`. Do **not** build this before phase 3 exists as
   a need; the git model covers a single tenant fine.

## 6. Recommended API changes

No APIs exist; the equivalent is the **refresh contract**. Codify it in-repo:

1. `seo-dashboard/REFRESH_RUNBOOK.md`: the exact tool calls + parameters used per module
   (already enumerated in §1/§2), extraction schemas for each JSON file, and the rule that all
   page arrays must be generated by `build.py` from snapshot JSON — **eliminate hand-typed
   arrays** (fixes problem 8).
2. Metric rules in the same runbook: MTD flags on partial months (render "Aug †" + normalized
   or prior-full-month comparisons), pooled-CTR only, movement labels must name their baseline
   ("since last index update"), dofollow computed on a single basis, AI claims carry method
   captions ("single run", "sampled corpus", "on tracked keywords").
3. AI answer testing: fixed prompt set (n≥3 phrasings × 2 models × ≥2 runs), store verdicts
   per run, report cited-in-k-of-n — replacing the single-run verdict.

## 7. Ordered implementation phases

- **Phase 0 — Preserve (do first, ~minutes):** commit template, build script, current
  snapshot JSONs, and this document to `claude/seo-ai-dashboard-lscekk`. (This commit
  intentionally contains only the audit doc; source/snapshots land in the first post-approval
  commit since "no code changes yet" was the instruction.)
- **Phase 1 — Metric correctness:** implement §6.2 labeling; reconcile keyword-count surfaces
  (pick the historical row as canonical, caption the others); regenerate all arrays from JSON.
- **Phase 2 — Repeatable refresh:** `build.py` reads `snapshots/<date>/`; add reconciliation
  assertions (§9); create a weekly refresh Routine; trend charts switch to reading the
  accumulated snapshot history.
- **Phase 3 — Multi-client:** `clients/<domain>.json` config (GSC property string, GA4
  property id, competitor list, AI prompt set, allowed-properties whitelist); one artifact per
  client; never cross-tenant in one page.
- **Phase 4 — AI-visibility hardening:** multi-run prompt panel per §6.3; mention trends from
  snapshot history.
- **Phase 5 (optional, decision gate):** hosted app (Supabase + web frontend) only if
  client-facing logins/live data become requirements. Not before.

## 8. Files likely to change

| File | Phase | Change |
|---|---|---|
| `seo-dashboard/IMPLEMENTATION.md` (this file) | 0 | committed |
| `seo-dashboard/dashboard_template.html` | 0–4 | imported from scratchpad; then: MTD captions, provenance labels, tab-nav scroll affordance, tap-friendly tooltips, card-style GSC tables |
| `seo-dashboard/build.py` | 1–2 | formalized injector: all arrays from JSON, assertions, single command |
| `seo-dashboard/snapshots/rocketlaunchmedia.com/2026-08-24/*.json` | 0, 2+ | dated raw pulls (keywords.json, gap.json exist; the hand-transcribed arrays get JSON sources on next refresh) |
| `seo-dashboard/REFRESH_RUNBOOK.md` | 2 | refresh contract + metric rules |
| `seo-dashboard/clients/*.json` | 3 | per-tenant config |

## 9. Tests required

1. **Build integrity:** output contains no `__*_DATA__` placeholders; JSON parses; every
   `document.getElementById` target exists (already implicitly checked by zero JS errors in
   Playwright — make explicit).
2. **Reconciliation assertions (fail the build):** position-distribution sum == canonical
   keyword count; monthly GSC rollups == sum of dailies; dofollow + nofollow == its stated
   basis; every KPI number traceable to a snapshot field.
3. **Render tests (Playwright, exists ad hoc — commit it):** 390px and 768px, light + dark,
   each tab: no horizontal body scroll, no JS errors, screenshots for eyeball diffs.
4. **Palette validation:** re-run the contrast validator only when tokens change (validated
   for both themes on 2026-08-23; single-hue charts + icon-and-text status colors).
5. **Refresh dry-run test:** runbook executed against stored fixture responses produces a
   byte-identical page (guards against extraction drift).

## 10. Questions that genuinely cannot be answered from the codebase

1. **Where should this live long-term?** Housing an SEO dashboard inside the Supabase Swift
   SDK repo is accidental. Dedicated repo, or keep the namespaced directory here?
2. **Who is the audience per artifact** — Ed only, team, or clients? This decides sharing
   policy, per-client artifacts, and how much internal candor (spam links, decline) stays on
   the page.
3. **Which clients get dashboards first**, and which GSC property form is canonical for each
   (several exist as both URL-prefix and `sc-domain:` with differing permission levels)?
4. **Refresh cadence and API budget** — weekly vs monthly; DataForSEO live-LLM tests cost real
   money per run (~$0.12/ChatGPT run observed); what's the per-client ceiling?
5. **What caused the Nov 2025 GA4 spike (1,899 sessions) and the post-March ranking slide?**
   (campaigns? site changes? a March core update?) — needs Ed's knowledge, not the code.
6. **Disavow appetite** for the August spam-link cluster: monitor (recommended) or act?
7. **Is the artifact-snapshot model acceptable as "the product"**, with refresh-by-request +
   scheduled Routine — or is live/self-serve data a requirement that justifies Phase 5?
