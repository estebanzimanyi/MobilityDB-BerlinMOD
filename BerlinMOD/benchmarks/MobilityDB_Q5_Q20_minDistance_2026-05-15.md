# MobilityDB — Q5 / Q20 with the minDistance canonical form

**Date**: 2026-05-15
**Platform**: MobilityDB on PostgreSQL 17.8
**Build**: MobilityDB #1007 (minDistance family) + the outer STBox
spatial-distance prune on `mindistance_tgeo_tgeo` (#1021).
**Dataset**: BerlinMOD scalefactor 0.005 — 1620 trips × 100 vehicles.
Parameter subsets `Licences1`, `Licences2`, `Regions1`, `Periods1`
defined as `LIMIT 10` / `LIMIT 10 OFFSET 10` over the canonical tables,
matching `berlinmod_load.sql`.
**Driver**: `EXPLAIN (ANALYZE, FORMAT JSON)` wrapper, the same
measurement the PL/pgSQL harness applies per query.

---

## Q5 — minimum spatial distance between two licence sets

Canonical SQL is now the natural per-pair aggregate over the
cross-join:

```sql
SELECT l1.Licence, l2.Licence, minDistance(t1.Trip, t2.Trip)
FROM Trips t1, Licences1 l1, Trips t2, Licences2 l2
WHERE t1.VehicleId = l1.VehicleId AND t2.VehicleId = l2.VehicleId
GROUP BY l1.Licence, l2.Licence;
```

| Form | Time |
|---|---:|
| `ST_Distance(ST_Collect(...), ST_Collect(...))` CTE workaround | 80.61 s |
| `minDistance(t1.Trip, t2.Trip)` aggregate, no STBox prune | 33.2 s |
| `minDistance(t1.Trip, t2.Trip)` aggregate + STBox prune (cold) | 16.3 s |
| `minDistance(t1.Trip, t2.Trip)` aggregate + STBox prune (hot) | 9.4 s |

The aggregate result is bit-identical to the ST_Collect workaround and
to `MIN(ST_Distance(trajectory(t1.Trip), trajectory(t2.Trip)))` on the
100-row result (validated against the array form on the same
cross-join). The speedup over the prior canonical form is 4.9x cold
and 8.6x hot.

## Q20 — ten closest vehicles to each region during each period

Canonical SQL uses the scalar minDistance inside the LATERAL inner
query:

```sql
SELECT v.Licence, minDistance(atTime(t.trip, p.Period), r.geom) AS Dist
FROM Trips t, Vehicles v
WHERE t.VehicleId = v.VehicleId AND t.Trip && p.Period
ORDER BY minDistance(atTime(t.trip, p.Period), r.geom)
LIMIT 3;
```

| Form | Time |
|---|---:|
| `trajectory(atTime(t.Trip, p.Period)) <-> r.geom` operator | 77.6 s |
| `minDistance(atTime(t.trip, p.Period), r.geom)` scalar | 72.6 s |

Q20 is essentially unchanged. The bottleneck is the per-trip `atTime`
restriction inside the LATERAL subquery, not the distance call; the
scalar minDistance reuses NAD's kernel so there is no extra speedup to
extract on this query shape. The earlier hypothesised 74 to 45 s gain
does not reproduce on this dataset and build.

---

## Reading

Q5 is the headline result of the minDistance rollout. The natural
form a cloud-SQL programmer would write, `minDistance(t1, t2)` grouped
over the cross-join, is now both the canonical query and the fast
query. The ST_Collect workaround was only ever fast under PostGIS
PreparedGeometry caching, which any instrumented or non-PostgreSQL
backend defeats; the bench EXPLAIN wrapper alone collapses it from
10 ms to 131 s. The minDistance aggregate carries its speed across
that boundary because the STBox prune and the threshold-aware sweep
are intrinsic to the kernel, not dependent on a per-call geometry
cache that exists only in PostgreSQL.

## Reproduce

```sql
CREATE TABLE Licences1 (LicenceId, Licence, VehicleId) AS
  SELECT LicenceId, Licence, VehicleId FROM Licences LIMIT 10;
CREATE TABLE Licences2 (LicenceId, Licence, VehicleId) AS
  SELECT LicenceId, Licence, VehicleId FROM Licences LIMIT 10 OFFSET 10;

EXPLAIN (ANALYZE, FORMAT JSON)
SELECT l1.Licence, l2.Licence, minDistance(t1.Trip, t2.Trip)
FROM Trips t1, Licences1 l1, Trips t2, Licences2 l2
WHERE t1.VehicleId = l1.VehicleId AND t2.VehicleId = l2.VehicleId
GROUP BY l1.Licence, l2.Licence;
```
