# Manila City GTFS

Subset of the Sakay.ph / DOTC Philippine GTFS feed (about 2013–15), clipped to the
**City of Manila** (PSGC 1380600000 boundary, faeldon/philippines-json-maps 2023).

531 stops · 599 routes (561 jeepney, 36 bus, LRT-1, LRT-2) · 663 trips

## How it was built
1. **Patched** (`tools/patch_gtfs.py`): calendar dates stretched to 2020-01-01 – 2035-12-31,
   blank `route_short_name` filled from the LTFRB code, and a Sunday LRT-1 trip added
   (`882223_sun`, service `FIX_SUNDAY`) because the source has no Sunday service toward Baclaran.
2. **Clipped** (`tools/clip_gtfs.py --tolerance-m 0`): a stop is kept only if it is inside the
   boundary polygon. Each trip is cut into runs of consecutive kept stops; a run of 2+ stops
   becomes its own trip (suffix `_a`, `_b`, as for trips `726109`, `726259` and `726260`), so no
   fake ride crosses a gap outside the city. Stop times are re-based so each run starts at
   00:00:00. Shapes are cut to the part inside the polygon.
3. **Cleaned up**: routes, services, agencies, stops and shapes left unused are removed.
   PNR Metro Commuter (`ROUTE_880872`) is excluded because it has no service in Manila, and
   MRT-3 does not enter the City of Manila.

Some trips therefore contain only the Manila portion of their original itinerary. Some
LTFRB stop names say Quezon City or Caloocan; those are LTFRB's labels, and the coordinates
are inside the boundary.

Original data: Metro Manila jeepney, bus and LRT services. See `LICENSE.md` for the DOTC
license terms, and `../README.md` for fares, rebuild steps and known gaps.