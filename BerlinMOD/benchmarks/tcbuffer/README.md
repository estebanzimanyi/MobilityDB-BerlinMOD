# Tcbuffer vs tgeompoint — noise-footprint benchmark

An executable Jupyter notebook that measures, on one full day of Danish AIS, what it costs and what it
buys to model a vessel as a moving **disk** (`tcbuffer` — centerline plus a time-varying noise radius)
rather than a moving **point** (`tgeompoint` centerline). It is a sibling of the MobilityAPI
[`tutorial`](https://github.com/MobilityDB/MobilityAPI/tree/master/tutorial) /
[`tutorial-stream`](https://github.com/MobilityDB/MobilityAPI/tree/master/tutorial-stream) notebooks
and of the [`CrossPlatform_timings`](../CrossPlatform_timings_2026-05-12.md) catalog: same AIS day, same
map idiom. Here the comparison axis is two models of the same trip on one engine (MobilityDB), with the
same operator timed on each.

## Contents

| File | What |
|---|---|
| `CrossModel_tcbuffer_timings.ipynb` | the executable benchmark (run it to reproduce the numbers) |
| `tcbuffer_timings.md` | the static catalog, exported by the notebook from the same run |
| `tcbuffer_vs_tgeompoint.svg` | the grouped per-operator chart, exported by the notebook |
| `tcbuffer_benchmark.sql` | the query catalog (single source of truth the notebook parses) |
| `tcbuffer_load.sql` | the loader that builds `VesselTrip` (`Trip` tgeompoint + `Noise` tcbuffer) and the protected-area polygons |

## Run it

```bash
# 1. MobilityDB at the ecosystem pin, cbuffer family enabled
cmake -DMEOS=OFF -DCBUFFER=ON -DPOSTGRESQL_PG_CONFIG=<pg>/bin/pg_config .. && ninja && ninja install

# 2. one full day of AIS (aisdk-2026-02-26.csv from https://web.ais.dk/aisdata/, plus the area CSVs)
createdb tcbuffer_bench
psql tcbuffer_bench -c 'CREATE EXTENSION mobilitydb CASCADE'
psql tcbuffer_bench -v data_dir=/path/to/csvs/ -f tcbuffer_load.sql -c 'SELECT tcbuffer_load(SF:=1)' -c 'ANALYZE'

# 3. execute the notebook (set the cross-join scale; larger N => longer run)
PGDATABASE=tcbuffer_bench TCBUFFER_N=50 jupyter nbconvert --execute --to notebook --inplace \
    CrossModel_tcbuffer_timings.ipynb
```

The temporal-output spatial relations (`tIntersects` / `tDwithin` / …) are held back by default
(`TCBUFFER_RUN_FRONTIER=1` to include them): against the high-vertex protected-area multipolygons a
single Noise evaluation runs for minutes and does not yield to cancellation.
