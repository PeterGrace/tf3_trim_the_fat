# Trim the Fat: average load from logged departures

Mod: `pgrace_trim_the_fat`. Changes the line card spec's **Avg load (A)** (`2026-10-10-line-card-design.md` §1).

## Problem

Avg load was `itemsTransported/yr ÷ (round trips/yr × capacity per vehicle × stops)`, with round trips/yr worked
out from today's interval (`1 / getMaxFrequency`) and each vehicle's time on the line. The numerator is a rolling
12 months, but the denominator is an estimate, so the two don't move together.

Seen in-game with a probe (Bus Passengers-Wyo-Pot-IC-1: 3 buses × 20 seats, 2 stops, a 166 s interval, so about 9
departures per stop a year):

| Items (12 mo) | Departures logged at a stop | Old load | Items ÷ (departures × stops × 20) |
|---|---|---|---|
| 341 | 9 | 96.9% | 95% |
| 361 | 10 | 102.6% | 90% |
| 321 | 9 | 91.2% | 89% |

The interval, capacity, vehicle count and stop count didn't change. Only the item count moved, by one busload (20,
about 6%) at a time as departures entered or left the 12-month window. The estimated 8.8 round trips a year fell
short of the 9–10 actual ones, so the load went over 100%.

## Change

Take both sides of the load from the line's stop logs, over the last year:

```
offered at a stop = Σ over its departures of max(capacity per vehicle, boarded)
load              = Σ boarded at all stops ÷ (stops × offered at the busiest stop)
```

- **Stop logs:** a line's LOG_BOOK has `itemsAtStop<k>_c<cargo>`, a running total of boarders with one entry per
  logged departure from stop k (AGENTS.md, "Stop logs"). An entry's boarded count is its rise over the entry before
  it. Entries at the same time in a stop's cargo logs are one departure: their boarded counts add up.
- **Capacity per vehicle:** `totalCapacity ÷ vehicleCount` (current load configuration).
- **Why max(capacity, boarded):** an entry can hold more than one of today's vehicles. Two bunched buses can share an
  entry, and a vehicle replaced by a smaller model boarded up to its old capacity. Either way the entry offered at
  least what boarded.
- **Why the busiest stop:** departures where nobody boards leave no entry. Every vehicle leaves every stop once per
  round trip, so the stop that offered the most is closest to the capacity every stop was offered.
- No stop can board more than it was offered, and none was offered more than the busiest, so **the load can't pass
  100%**. The departures are counted, so vehicles bought recently only add the trips they made; `vehicleDataMs`
  isn't needed on this path.
- **Numerator:** the boardings in the stop logs, not the line's `itemsTransported`. The two differ by a few percent
  at the window's edges (seen: 740 vs 760, 60 vs 50), and the stop logs match the denominator's window exactly.
- **Fallback:** with nothing in the stop logs (a new line, or no logs), use the old interval formula unchanged.
- **Known gap:** a replaced vehicle that ran part-full under its old, larger capacity counts as today's capacity, so
  the line reads a little high until those trips leave the window. The game keeps no record of old capacities.

The UI text is unchanged: the line card's tooltip already says "capacity × departures × stops".

## What the probes showed (2026-10-12, a save with 126 bus lines)

- **Departures where nobody boards aren't logged:** no zero entries in 300 readings. Noc-LO-1 (1 bus, 3 stops,
  about 8.4 round trips a year) logged 5, 5 and 8 departures at its stops.
- The stop logs reach back more than a year (oldest entries 1.08–1.20 years old).
- **Entries can hold more than a vehicle:** Sou-PerHal-IC-1 (9 × 20-seat buses, 2 stops) logged 740 boarders in 34
  entries, 21.8 per entry. The line had 28-seat buses replaced by 20-seat ones; bunching may add to it. Counting
  entries as departures read 112%.

## Tests (`tests/metrics_test.lua`)

- `stopTotals`: boarded and offered per departure, with the first entry giving only the starting total; entries
  before the window; a bunched entry and a bigger old vehicle offering what boarded; cargo logs at the same time
  as one departure; empty and missing logs.
- `averageLoad` with stop totals: a quiet stop doesn't lower the offered capacity; the interval, `dataMs` and
  `vehicleDataMs` are ignored; nothing logged falls back to the interval formula.
