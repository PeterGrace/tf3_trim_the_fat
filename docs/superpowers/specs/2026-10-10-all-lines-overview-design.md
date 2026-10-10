# Trim the Fat: all-lines overview design

Builds on the line card (`2026-10-10-line-card-design.md`), whose verdict logic and findings apply unchanged.

## Problem

The line card judges one line at a time. With well over 40 lines, the player needs one list of every line with its
verdict, worst first, to decide where to trim. The base F2 Lines table can't take a column: its tabs and columns are
fixed lists in `gui/statistics/` with no extension point.

## §1 Button and window

- **Button:** a plugin on `::MainModButtonAreaExtension` (`gui/main/main_mod_button_area.tl`), the game bar's area
  for mod buttons; the game shows the area once any plugin is registered. A button with a tooltip
  ("Trim the Fat").
- **Window:** like F2 Statistics (`gui/statistics/statistics.tl`): a tool registered with
  `tool_react_util.registerToolWithWindow(toolName, windowId, WindowRecipe)`, pushed on the click with
  `game_react_globals.getDefaultToolStackApi().push(tool, nil, toolParam)` and popped by the window's `onClose`
  (✕, Esc). The window recipe wraps `builtin.Window{ id, title, tool, closable = true, onClose, content }`.
- **Fallback** if pushing a mod tool fails: a plugin on `::ModEntryPointExtension` (children of the game UI root's
  floating layout) renders the `builtin.Window` while an `open` state is true; the button toggles it with
  `react.fireEvent`.
- **Probe round 1** (temporary `debugPrint`, marked `-- PROBE (remove before release)`): the button appears, the
  window opens and closes (✕, Esc, button again), it coexists with F2 and a line window, and the log shows how long
  computing all lines took and how many lines there were.

## §2 Data

- **Shared line input:** `line_data` gets `lineInput(line)`, the line-level part of `snapshot`: money, transported,
  capacity, interval, stops, `dataMs`, `vehicleDataMs` (Σ each vehicle's `dataSpan`), cargo types, passengers,
  load now, carrier and noun. `snapshot` calls it and adds the vehicle rows, so the card and the window always
  agree. The window skips the per-vehicle names, ages and formatting.
- **Lines:** `api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer())`, as the F2 Lines table.
- **Per line:** `metrics.assess(lineInput(line).input)`, each in its own `pcall`. A failed line keeps its row,
  shows "Error" in the verdict column and is logged once.
- **Computed once** when the window opens and again on ⟳. Values are frozen in between, so rows never re-sort
  while the player reads.
- **Performance:** if probe round 1 shows more than ~100 ms on the player's save, compute a batch of lines per
  frame instead (rows fill in, a "Calculating… n/N" line shows progress, totals settle when done). `lineInput` is
  the same either way.
- **Summary** (pure, unit-tested): `metrics.summarise({Assessment}) : Summary` with `losingCount`,
  `losingPerYear` (Σ balance per year of Losing lines), `tooManyCount` (lines with trim > 0, any verdict) and
  `trimTotal` (Σ trim).

## §3 Window

```
Trim the Fat                                                              [⟳] [✕]
[Road] [Tram] [Rail] [Ship] [Air]
23 losing money: $-4,812,330 per year · 17 with too many vehicles: up to 58 to remove
──────────────────────────────────────────────────────────────────────────────────
Line ↕                     Verdict ↕                  Per year ↕   Load ↕  Vehicles ↕
▌⌖ RC Fertilizer…          Losing · not delivering    $-627,335     9%     2 trucks
▌⌖ Bus CouClu-LO-3         Losing money (−11)         $-409,456    19%    15 buses
▌⌖ Bus 4                   Too many (−2)              $+41,200     38%     7 buses
▌⌖ Coal Express            OK                         $+412,000    74%     8 trains
```

- **Filters:** five toggles with the F2 icons (`::/gui/statistics/icons/vehicle_{bus,tram,train,ship,airplane}_18.tga`
  and F2's tooltips), all on at first, combined as in F2 (`line_util.filterLine(allowedCarriers, line)`). Rows are
  hidden with `fnUserFilter`; `rowKeys` only changes on ⟳.
- **Summary line:** follows the filters (only shown lines count). Parts with a zero count are left out; with nothing
  to report it reads "No lines are losing money or have too many vehicles."
- **Columns** (`builtin.DataTable`):
  - **Line:** `line_react_util.ColorWidget` + `line_react_util.NameTextView{ entity, locationButton = true,
    stackEntityOpen = true }` as F2 (locate button, name opens the line window).
  - **Verdict:** colour classes as the card (`negative` Losing, `warning` Too many / Busy, `positive` OK). Texts:
    "Losing money", "Losing money (−N)", "Losing · not delivering", "Too many (−N)", "Busy", "OK", "Too new",
    "No vehicles", "Error". `metrics.verdictKind(assessment)` (pure) picks the label ("Losing", "LosingTrim",
    "LosingStuck", "TooMany", "Busy", "Ok", "TooNew", "NoVehicles") and its severity; the script maps each kind
    to its translated text. Sorted by severity (Losing kinds, Too many, Busy, Too new, No vehicles, OK; Error
    last), then by Per year.
  - **Per year:** balance per year, `*` when annualised (footnote under the table, as the card).
  - **Load:** average load, "—" when unknown.
  - **Vehicles:** the card's plural noun ("15 buses").
- **Initial sort:** Per year, ascending (worst first). The player's sort is kept across ⟳.
- **Empty state:** "No lines yet."

## §4 Localisation

As the card (see its §3): every new text through `_()` in all 12 languages, plural keys for the summary counts
("{count} losing money|one/few/many/other", "{count} with too many vehicles|…", "up to {count} to remove|…"),
`_("{percent}%")` for loads, `api.util.formatMoney` for money. Terms follow `base.mo` ("Lines", "Road", ...).

## §5 Structure

```
content/gui/pgrace_trim_the_fat/
├── metrics.tl                # + summarise, verdictKind (pure)
├── line_data.tl              # + lineInput (snapshot uses it), playerLines
├── overview.script.tl        # button plugin, tool + window, table
├── overview_button.res.lua   # react-plugin ::MainModButtonAreaExtension
├── line_card.script.tl       # unchanged apart from the shared line input
└── line_card.res.lua
```

## §6 Errors

- Everything that reads the engine runs in `pcall`; a failed line shows "Error", a failed whole computation shows
  "Error (see log)" with the ⟳ button still available.
- Every recipe returns a layout, cell recipes included.
- If the tool stack API is missing (`getDefaultToolStackApi` nil or throwing), log it and use the §1 fallback.

## §7 Testing

- `tests/metrics_test.lua`: `summarise` (counts, sums, a line that is both Losing and has a trim, empty input) and
  `verdictKind` (each verdict, Losing with a trim, not delivering, severity order).
- `just verify` (type-check, tests, release check with translations).
- **In-game round 1:** the §1 probe.
- **In-game round 2:** filters and summary, sorting, locate and opening a line, ⟳, German, and the window's verdict
  matching the line card on two or three lines.

## Findings (in-game)

- **Round 1:** the `MainModButtonAreaExtension` button shows at the screen's top left, next to the map-layers button
  (not in the bottom bar). Pushing a mod tool on the default tool stack with a `gameCtx` built from
  `game_react_globals` works; the button shows pressed while the window is open. 116 lines took 45 ms, so the
  window computes everything on open. Without a size the window shrinks to its content at the top left: give it
  `initialX/Y` and a stylesheet size.
