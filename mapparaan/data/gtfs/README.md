# Manila City GTFS

Subset of the Sakay.ph / DOTC Philippine GTFS feed, clipped to the **City of Manila**
(PSGC 1380600000 boundary, faeldon/philippines-json-maps 2023).

## How it was clipped (`tools/clip_gtfs.py`)
1. **Stops**: kept if inside the boundary polygon or within 50 m of its edge (source
   coordinates are rounded to ~55 m); a stop in that edge band is skipped if its name
   names another city.
2. **Trips**: each trip is cut into runs of consecutive kept stops. A run of 2+ stops
   becomes its own trip (suffix `_a`, `_b`), so no fake ride crosses a gap outside the
   city. Stop times are re-based so each run starts at 00:00:00.
3. **Shapes**: cut to the part inside the polygon.
4. **Cleanup**: routes, services, agencies, stops and shapes left unused are removed.

Some trips therefore contain only the Manila portion of their original itinerary.

Original data: Metro Manila jeepney, bus, LRT and PNR services (MRT-3 does not enter the
City of Manila). See `LICENSE.md` for the DOTC license terms.