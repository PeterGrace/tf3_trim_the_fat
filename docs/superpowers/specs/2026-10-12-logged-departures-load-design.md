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
offered at a stop = Σ over its logged arrivals of max(capacity per vehicle, carried)
load              = Σ carried into all stops ÷ (stops × offered at the busiest stop)
```

- **Stop logs:** a line's LOG_BOOK has `itemsAtStop<k>_c<cargo>`, a running total with one entry each time a vehicle
  **arrives** at stop k with anything on board. The entry's rise over the one before is what was on board as the
  vehicle pulled in, before anyone got off (AGENTS.md, "Stop logs"). So it measures each leg's load, and a rider who
  stays aboard through a stop counts on each leg. Entries at the same time in a stop's cargo logs are one arrival:
  their counts add up.
- **What the load means:** average occupancy per leg, the same idea as seat occupancy. It runs above
  `itemsTransported ÷ capacity` on lines with more stops, because `itemsTransported` counts each rider once.
- **Capacity per vehicle:** `totalCapacity ÷ vehicleCount` (current load configuration).
- **Why max(capacity, carried):** an entry can hold more than one of today's vehicles. A vehicle replaced by a smaller
  model carried up to its old capacity, and two vehicles arriving in the same tick would share an entry. Either way
  the arrival offered at least what it carried.
- **Why the busiest stop:** a vehicle arriving empty leaves no entry. Every vehicle arrives at every stop once per
  round trip, so the stop that offered the most is closest to the capacity every stop was offered.
- No stop can be carried into beyond what it was offered, and none was offered more than the busiest, so **the load
  can't pass 100%**. The arrivals are counted, so vehicles bought recently only add the trips they made;
  `vehicleDataMs` isn't needed on this path.
- **Fallback:** with nothing in the stop logs (a new line, or no logs), use the old interval formula unchanged.
- **Known gap:** a replaced vehicle that ran part-full under its old, larger capacity counts as today's capacity, so
  the line reads a little high until those trips leave the window. The game keeps no record of old capacities.

**Tooltip:** the line card's load tooltip said a passenger riding several stops counts once, so lines with many stops
read lower than seat occupancy. It now reads "Average load: what the vehicles carried between stops in the last 12
months ÷ their capacity on those legs. A passenger riding several stops counts on each leg, as in seat occupancy.",
in all 12 languages.

## What the probes showed (2026-10-12, a save with 126 bus lines)

- **What an entry is:** on PerHal-LO-2 (4 stops, 5 buses), a probe logged each bus's arrivals and loading states and
  each new stop-log entry. 364 of 372 entries equalled the passengers on board as a bus arrived at that stop (one
  mismatch; 7 arrivals missed by the probe). All 365 arrivals with people aboard had an entry; none of the 19 empty
  arrivals did. An entry's timestamp is the arrival, not `TransportVehicle.lastLineStopDeparture` (which read
  about 360 s behind the game time).
- **Why the logs run above `itemsTransported`:** the median ratio of the logs' total to `itemsTransported` was 1.00
  on 2-stop lines, 1.20 with 3 stops, 1.32 with 4 and 1.41 with 5. Riders staying aboard through a stop are counted
  on each leg.
- The stop logs reach back more than a year (oldest entries 1.08–1.20 years old).
- **Entries can hold more than a vehicle:** Sou-PerHal-IC-1 (9 × 20-seat buses, 2 stops) logged 740 in 34 entries,
  21.8 per entry. The line had 28-seat buses replaced by 20-seat ones. Counting entries as departures read 112%.
- **Adding vehicles:** PerHal-LO-2 went from 3 to 5 buses. Its load didn't move at first (the new buses hadn't
  arrived anywhere yet), then fell from 56% to 46.6% over half a year while its riders grew by 13%.

## Tests (`tests/metrics_test.lua`)

- `stopTotals`: carried and offered per arrival, with the first entry giving only the starting total; entries
  before the window; an entry holding more than a vehicle offering what it carried; cargo logs at the same time
  as one arrival; empty and missing logs.
- `lineStopTotals`: carried summed over the stops, offered at the busiest.
- `averageLoad` with stop totals: a quiet stop doesn't lower the offered capacity; the interval, `dataMs` and
  `vehicleDataMs` are ignored; nothing logged falls back to the interval formula.
