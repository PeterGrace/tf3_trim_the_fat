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

Count the departures the line actually made over the last year, and use them for the capacity offered:

```
offered = stopDepartures × stops × capacity per vehicle
load    = itemsTransported/yr ÷ offered
```

- **`stopDepartures`**: the most departures logged at any one stop over the last year. A line's LOG_BOOK has
  `itemsAtStop<k>_c<cargo>`, one entry per departure from stop k (AGENTS.md, "Stop logs"). At each stop, a
  departure counts once across the cargo logs (entries are matched by time). Every vehicle leaves every stop once
  per round trip, so the stops' counts differ by a few vehicles at most. Taking the busiest stop guards against a
  stop that logs nothing for empty departures (not yet confirmed either way).
- **Capacity per vehicle**: `totalCapacity ÷ vehicleCount`, as before (current load configuration).
- Because the departures are counted, not estimated, the vehicles' own time on the line (`vehicleDataMs`) isn't
  needed on this path: a vehicle bought last month only adds the departures it made.
- **Fallback**: with no logged departures (a new line, or no stop logs), use the old interval formula unchanged.

Numerator and denominator now cover the same 12 months and rise and fall together, so a sparse line reads steady,
and the load can't pass 100%: no departure boards more than a vehicle holds.

The UI text is unchanged: the line card's tooltip already says "capacity × departures × stops".

## Risks, checked with the probe

- Whether a departure that loads nothing still logs an entry (affects only stops other than the busiest).
- Whether the stop logs reach back a full year. If they're shorter, departures are undercounted and the load reads
  high. The probe logs the oldest entry's age and the items summed from the stop logs, to compare with
  `itemsTransported`.

## Tests (`tests/metrics_test.lua`)

- `countDepartures`: distinct entry times after a time across several logs; empty and missing logs.
- `averageLoad` with `stopDepartures`: the Wyo-Pot-IC-1 numbers give 90%; the interval, `dataMs` and
  `vehicleDataMs` are ignored; 0 or nil falls back to the interval formula.
