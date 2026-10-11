# Trim the Fat: line card design

Mod: `pgrace_trim_the_fat` (display name "Trim the Fat"). UI-only, `cosmetic: true`.

## Problem

The base game shows a vehicle's or line's **Balance** and **Utilization**, but they measure different things:

- **Balance** is a rolling 12 months: income minus running and maintenance costs over the last game year, purchase
  price excluded (`calculateBalance(entities, now - yearDuration, now, maintenanceIncomeOnly = true)` in
  `vehicle_react_util.tl` / `line_react_util.tl`). A vehicle bought three months ago has only three months in it.
- **Utilization** is an instant snapshot: cargo on board ÷ capacity right now
  (`statistics_react_util.calculateCargoColumnData`). A vehicle that just unloaded reads 0%.

Comparing a year-long average with a snapshot makes it hard to tell which lines lose money and which have too many
vehicles. The mod puts comparable numbers side by side and gives a verdict.

## Scope

This spec: a card in the **line window** (`LineEowExtensionPoint`), fully localised.

Later, in separate specs:
- a company-wide "all lines" overview, opened from the game bar (`GameBarInfoDisplayExtension`; this entry point
  is unproven);
- a background load sampler that saves history (approach B). It would make the mod non-cosmetic, so we'll build it
  only if the derived load turns out to be too inaccurate.

## §1 Numbers (`metrics.tl`, pure, unit-tested)

Per line, over the last game year:

| Value | Definition |
|---|---|
| Balance/yr | Sum of the line's vehicle balances (purchase price excluded, as in the base game) |
| Profit per vehicle | Balance ÷ vehicle count |
| Avg load (A) | `itemsTransported/yr ÷ (round trips/yr × Σ vehicle capacity ÷ vehicles × stops)`: each round trip runs one leg per stop, and every leg offers the vehicle's capacity. Round trips/yr is the data window ÷ the line's interval (`1 / getMaxFrequency`). Reads lower than seat occupancy on multi-stop lines, because a rider is counted once, not once per leg. |
| Now load (C) | Σ cargo on board ÷ Σ capacity across all of the line's vehicles at this moment |
| Target | `TARGET_SINGLE_CARGO = 0.50` only for freight lines carrying exactly one cargo type (empty backhaul); `TARGET_DEFAULT = 0.70` for passenger and mixed-cargo lines. Passengers are one cargo type, but riders travel both ways. |

Verdict (first match wins):

1. **TOO_NEW**: line has under `MIN_DATA_DAYS` (≈ 1 month) of data. Shows "Too new to judge".
2. **LOSING**: balance/yr < 0. If load A is also below target, the trim suggestion is shown as well.
3. **TOO_MANY**: load A < target and vehicles > 1. `keep = max(1, ceil(vehicles × loadA ÷ target))`,
   `trim = vehicles − keep`. If trim is 0, the verdict falls through to OK.
4. **BUSY**: load A ≥ `BUSY_LOAD = 0.95`. Shows "may need more vehicles".
5. **OK**.

If capacity is 0, or the interval or stop count is unknown, load A is "—" and neither TOO_MANY nor BUSY can be the verdict.

Frequency attracts riders, so fewer vehicles can mean less demand. The suggestion is an upper bound ("try removing up
to N"), and the tooltip recommends trimming one vehicle at a time.

Per vehicle:
- **Age:** time since purchase.
- **Balance/yr:** if age < 1 year, annualise it (`balance × year ÷ age`) and mark it `*`.
- **Load now:** the vehicle's current load (C). Per-vehicle load A is added only if probe 1 shows that vehicles have
  their own `itemsTransported` log.

All thresholds are named constants in `metrics.tl`; 70/50 are a starting point, calibrated after the first in-game
test.

## §2 Card

```
┌ Trim the Fat ────────────────────────────────────┐
│ ● TOO MANY: try removing up to 2 trains            │
│ $412k/yr · $52k per vehicle · 8 trains             │
│ Avg load 34% (target 50%) · now 41%                │
├──────────────────────────────────────────────────┤
│ Vehicle ↕      Age ↕   $/yr ↕     Load now ↕   [⌖]  │
│ Coal Train 8   3mo     −$36k*     18%         [⌖]  │
│ Coal Train 7   2y      +$12k      22%         [⌖]  │
│ Coal Train 3   4y      +$88k      61%         [⌖]  │
│ * annualised from less than a year of data         │
└──────────────────────────────────────────────────┘
```

- `content_card.ContentCard` wrapper, as in the base cards. Card title: "Line efficiency".
- **Verdict:** the verdict text in the game's colour classes: `negative` (LOSING), `warning` (TOO MANY / BUSY),
  `positive` (OK), default (TOO NEW / no vehicles). The base UI has text colour classes but no dot widget. The
  text sits in a button, so it can have a tooltip that shows the calculation
  (e.g. "8 × 34% ÷ 50% = 5.4 → keep 6").
- **Vehicle table:** `builtin.DataTable`, click-to-sort headers, initially sorted by $/yr ascending (worst first).
  - Name column: `line_react_util.makeEntityWindowButton` (opens the vehicle window, where the base sell button is).
  - Locate column: `line_react_util.LocateButton`.
  - Text columns get weights; narrow numeric columns may use icon headers.
- **No sell button of our own.** Selling is irreversible and the base window already does it.
- **Refresh:**
  - The headline and table data are computed once per mount (`react.useStateLazy` + `pcall`).
  - "Now" loads poll with `engine_react_util.useStepStateTimer(fn, 0.25)`.
  - Sorting reads a snapshot refreshed in `onSortColumnChange`, so rows don't re-sort on live updates.
- **Placement:** `order = 55`, between the line's vehicle list (50) and income graph (60).

## §3 Localisation

Following the Commuter Compass approach (see AGENTS.md "Translations"):

- **Text:** every visible string goes through `_("...")`, with English keys. Placeholders use `{name}` and are
  filled with `lang_util.format`.
- **`mod/pgrace_trim_the_fat/strings.json`:** contains all 12 TF3 languages (de, es, fr, it, ja, ko, nl, pl, pt_BR,
  ru, zh_CN, zh_TW). Wording follows the base game's terms; look them up in `base/strings/<lang>/LC_MESSAGES/base.mo`
  (Balance, Utilization, Load, Train, Bus, ...).
- **Plurals:** "{count} vehicles" and the trim suggestion use one key per plural form. Ages come from
  `api.engine.util.formatAge`, which is already localised
  (`|one`, `|few`, `|many`, `|other`). `metrics.pluralCategory(languageCode, count)` (ported from Commuter Compass
  `rank.pluralCategory`, unit-tested) picks the form for `app.getUserProfile():getLanguage().code`. English has
  `strings.json` entries for the plural keys.
- **Vehicle-type nouns** (train/bus/truck/ship/plane/tram) in the verdict come from the line's transport mode, each
  as its own plural key set. If the mode can't be found, fall back to "vehicles".
- **Numbers:**
  - money: `api.util.formatMoney`;
  - integers: `api.util.lang.formatInt`;
  - percentages: `_("{percent}%")` (German `"{percent} %"`);
  - decimals: the key `{integer}.{decimal}`, so each language picks its decimal separator.
  Format at compute time and store the text; the 0.25 s poll formats only its own percentage.
- **Mod Hub text:** `_metadata/modinfo.json` gets `localization` for all 12 languages (name, summary, description).
  `description.html` stays English.
- **Release check:** `tools/release_check.py` (already the Commuter Compass version) fails on missing keys, lost
  placeholders or unknown languages.

## §4 Structure

```
content/gui/pgrace_trim_the_fat/
├── metrics.tl              # pure: targets, load, verdict, trim, annualise, explanation, pluralCategory
├── line_data.tl            # api.engine only here: builds a plain LineSnapshot record
├── line_card.script.tl     # UI
└── line_card.res.lua       # react-plugin ::LineEowExtensionPoint
```

The template's `util.tl` / hello card and its test are removed. `line_data.tl` is meant to be reused by the
overview later.

## §5 Errors

- Data gathering runs in `pcall`. On failure the card shows "error (see log)" and the error is logged with
  `debugPrint("[trim_the_fat] ...")`.
- The plugin `condition` returns true on error.
- Explicit states for: no vehicles ("No vehicles"), zero capacity / unknown interval (load "—"), too new.
- API calls missing from the tealdefs go through a local record cast and are nil-checked.
- Every recipe returns a layout (never a bare widget), including DataTable cell recipes.

## §6 Testing

- `tests/metrics_test.lua` covers:
  - every verdict branch, including the LOSING + trim combination;
  - trim rounding (keep never below 1, trim 0 falls through to OK);
  - single-cargo freight vs default target (passenger lines get the default);
  - annualising below / above one year;
  - zero capacity and unknown interval;
  - `pluralCategory` for en/fr/pl/ja.
- `just verify` (type-check, tests, release check including translations) must pass.
- **One combined in-game round on the first build:**
  - **Probe 1:** do vehicles have their own `itemsTransported` log (`getLogValuePerYear(vehicle, "itemsTransported")`)?
  - **Probe 2:** which API gives the line interval / round-trip time, and what are load A and C on 3–4 real lines
    (for calibrating 70/50)?
  - **Checklist:**
    - card placement;
    - verdict + tooltip;
    - sorting stability;
    - name and locate buttons;
    - the `*` annualised marker;
    - one non-English language (German) for layout and plural forms.
  - Probes are marked `-- PROBE (remove before release)` and removed afterwards; findings go into this spec or
    AGENTS.md.

## Findings (in-game, 2026-10-10)

- `getMaxFrequency` is departures per second: 0.01094 → an interval of 91 s (the line window showed 97 s, read at a
  different moment).
- The line balance from `calculateBalance({line})` equals the sum of the per-vehicle balances (2 258 769). The base
  Balance card's "Last Year" (2 418 472) is a different window: the previous calendar year, like the chart's bars.
  That difference is the "lifetime or per year?" confusion this mod started from.
- Vehicles have an `itemsTransported` log, but it reads 0, so per-vehicle average load isn't available.
- On bus lines, capacity with `allCapacities` true equals capacity with it false.
- Load A first ignored the stop count and read 180% on a 2-stop bus line. With × stops, the same line (574 items,
  interval 91 384 ms, year 1 461 000 ms, capacity 140, 7 vehicles, 2 stops) reads about 90%, matching the live load
  of 89–100%.
- **Not delivering.** A freight line can lose money while its vehicles sit full (cargo loaded but never unloaded,
  e.g. no acceptor at the far end): average load 5–9%, load now 85–100%. Removing vehicles is the wrong advice
  there, so `assess` sets `notDelivering` (load now ≥ `STUCK_LOAD_NOW = 0.75` and average load <
  `STUCK_AVERAGE_LOAD = 0.25`), the card shows a hint instead of the trim suggestion, and the verdict is unchanged.
  The cut-off started at 90%, but a two-truck line at 100% + 70% read 85% and the advice flipped between visits.
- **Replacing a vehicle** keeps its entity, name and balance history and resets only `purchaseTime`. Annualising
  from the purchase time turned a full year's −323k into −1.2M. The data span is now measured from the first
  month in the last year with any money booked (`dataSpan` in `line_data.tl`), for vehicles and the line alike, so
  a replaced vehicle's "Per year" covers the slot, not the body. Age still shows the body's age, as the base game.
  The card's refresh row watches each vehicle's purchase time as well as the count, so it also offers a refresh
  after a replacement.
- **German pass:** "Macht Verlust", "6 Lkws · 2 Halte", "Ø Auslastung 2 % (Ziel 70 %)", header widths all fit.
- **Average load uses vehicle-time** (from the final review). The interval is today's, but the items cover the
  year, so buying vehicles made the year look underused ("remove 4 buses" right after adding them). Offered
  capacity is now Σ each vehicle's own data span ÷ round-trip time (interval × vehicles) × capacity per vehicle ×
  stops. Sold vehicles' time can't be counted, so right after a trim the load reads a little high until their
  months roll out of the year.
- **Many stops** (the review's concern that × stops undercounts riders who travel several legs): a 7-stop bus line
  with 16 buses read an average load of 19% while the live load was 24–30% across three looks, so riders average
  about 1.5 legs and the average reads roughly a third low there. Not enough to flip its verdict; revisit if a long
  line with visibly full vehicles gets "Too many".
- **Selling a vehicle** with the card open: the row's locate button disappeared, then came back seconds later
  (presumably its ID was reused), so the row checks that the vehicle is still listed on the line, not only that
  the entity exists.
- **Backlog** (2026-10-10): a 7-stop bus line with 290 passengers waiting at its hub read an average load of 35% and
  got "Too many vehicles". The average undercounts on lines with many stops, and it never looked at waiting
  passengers. `line_data` now reads the most passengers waiting at any of the line's stops
  (`getLineStopSimEntitiesCount`), and `assess` treats a busload or more (`BACKLOG_VEHICLES = 1` × capacity per
  vehicle) as a backlog: no trim, verdict Busy unless Losing, and the card shows how many are waiting.
- **Young vehicles:** "Per year" for a vehicle shows "Too new" until it has half a year of data
  (`MIN_VEHICLE_DATA_FRACTION = 0.5`). One month still showed a 2-month-old bus at -116,492* (its depot run and
  first trips scaled up 6×); the user chose six months over three. A whole line's Too new stays at one month.
- **Queue-limited trim:** on CouClu lines with a big backlog at the train station, a bus added for the backlog was
  suggested for removal once the queue cleared (the low average load decided the trim alone), and removing it brought
  the backlog back. Fewer vehicles stretch the interval by count ÷ keep, and the queues grow with it, so a trim now
  keeps at least `ceil(count × waitingMax ÷ (TRIM_QUEUE_LIMIT × capacity per vehicle))` vehicles, with
  `TRIM_QUEUE_LIMIT = 0.5`. The gap between half a busload (trim stops) and a whole busload (Busy) is the hysteresis.
  `queueLimited` marks it; the verdict tooltip says how many are waiting. The waiting count is a snapshot: a look
  just after a pickup reads low. If that proves too jumpy, remember each line's largest queue for the session.
- **Thin margin** (2026-10-11): a one-bus line with 26 waiting read Busy at +$115 a year; its running costs were
  $108k a year and its income about $100k, so a second bus would have lost money. Probe: `getAccountChart(line,
  config)` (what the Balance card draws) returns `series = { {years, income}, {years, running costs} }`, one entry
  per calendar year for the line's whole life (186 years here), the current partial year last. Costs are positive.
  A Busy line whose balance is under `THIN_MARGIN = 0.2` of its last full year's running costs now reads "Busy, but
  another vehicle would likely lose money" (overview: "Busy · thin margin") and leaves the busy count.
- **Purchases** aren't in `calculateBalance` for the line or its vehicles, with either flag: a lifetime balance only
  says whether the line covered its running costs.
- **Declining** (2026-10-11): comparing the last full year with the 5 before flagged noise. A freight line earns in
  batches of about $151k (three, two or one a year), and a bus line swung ±60% a year. The last 3 full years against
  the 5 before them (`metrics.trend`) fixed both. Running costs stayed within about 2% on every line, so income
  decides. Sorted by percentage, the top of the list was lines that always lost money, so a line must also have
  made money over the earlier 5 years. Under `DECLINE_RATIO = 0.75` that flagged 4 of 151 lines, three of them
  through one town. 151 lines took 18.5 ms. It's a marker (↘, a card hint and an overview filter), not a verdict.
- **Recently changed** (2026-10-11): a line's LOG_BOOK holds `itemsTransported`, `itemsTransported0` and per stop
  `itemsAtStop<stop>_c<cargo>` and `itemsAtStopUnsatisfied<stop>_c<cargo>`, but no vehicle count. A sold vehicle
  leaves no trace. So additions and replacements come from purchase times, which are saved with the game, while
  sales and vehicles moved between lines come from a per-session memory of each line's vehicle list in `line_data`,
  which starts empty after a restart. A change younger than `RECENT_CHANGE_FRACTION = 0.25` of a year gives
  `changedRecently`: a card note and the overview's "Hide changed" toggle. The unsatisfied-at-stop logs may be a
  better backlog signal than the waiting snapshot; not explored yet.
