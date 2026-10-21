# Manila City GTFS (Cleaned & Strictly Focused)

Cleaned subset of the Sakay.ph / DOTC Philippine GTFS feed, restricted to **Manila City** only.

## What was done
1. **Geographic filter**: Kept only stops whose coordinates fall inside the City of Manila bounding box  
   (lat 14.5495–14.6434, lon 120.9205–121.0343).
2. **Related entities**: Kept stop_times, trips, routes, shapes, frequencies and calendar entries that refer to those Manila stops.
3. **Agencies**: Only the agencies that operate the retained routes (LRTA, LTFRB, MRTC, PNR, etc.).
4. **Cleaning**: Removed unused records; preserved original field structure so the feed remains valid GTFS (note: some trips now only contain the Manila portion of their original itinerary).

## Result
- Stops: only those inside Manila City
- Routes & trips: those that serve Manila City
- Ideal for analysis or applications focused exclusively on the City of Manila.

Original data: Metro Manila jeepney, bus, LRT, MRT & PNR services.
