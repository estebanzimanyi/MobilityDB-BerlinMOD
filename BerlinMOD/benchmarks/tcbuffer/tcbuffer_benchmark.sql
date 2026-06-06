/*****************************************************************************
 *
 * This MobilityDB code is provided under The PostgreSQL License.
 * Copyright (c) 2016-2025, Université libre de Bruxelles and MobilityDB
 * contributors
 *
 * MobilityDB includes portions of PostGIS version 3 source code released
 * under the GNU General Public License (GPLv2 or later).
 * Copyright (c) 2001-2025, PostGIS contributors
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without a written
 * agreement is hereby granted, provided that the above copyright notice and
 * this paragraph and the following two paragraphs appear in all copies.
 *
 * IN NO EVENT SHALL UNIVERSITE LIBRE DE BRUXELLES BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING
 * LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION,
 * EVEN IF UNIVERSITE LIBRE DE BRUXELLES HAS BEEN ADVISED OF THE POSSIBILITY
 * OF SUCH DAMAGE.
 *
 * UNIVERSITE LIBRE DE BRUXELLES SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON
 * AN "AS IS" BASIS, AND UNIVERSITE LIBRE DE BRUXELLES HAS NO OBLIGATIONS TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
 *
 *****************************************************************************/

/*****************************************************************************
 * tcbuffer benchmark queries
 *
 * Side-by-side comparison of the spatio-temporal function catalog applied to
 * two models of a vessel trip:
 *   - VesselTrip.Trip  : tgeompoint (centerline)
 *   - VesselTrip.Noise : tcbuffer   (centerline + time-varying noise radius)
 *
 * Each catalog query is issued twice (once per model) so that wall time and
 * result count can be read off in pairs. The script also exercises the
 * (tcbuffer, cbuffer) and (Trip, Trip) pairings and ends with a showcase of
 * the cumulative noise footprint reaching protected areas that the centerline
 * never crosses.
 *
 * Required objects:
 *   VesselTrip100   (TripId, Trip tgeompoint, Noise tcbuffer)
 *   NaturalAreas100 (id, geom geometry)
 *   NaturalAreasCb100 (id, cb cbuffer)
 *
 * Run with psql \timing on (auto-enabled below):
 *   tcbuffer_sf1=> \i tcbuffer_benchmark.sql
 *****************************************************************************/

\timing on

/*****************************************************************************
 * Section A - Trip x geometry: tgeompoint vs tcbuffer
 *****************************************************************************/

/* A1 - Restriction by geometry / stbox */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE atGeometry(Trip, geom) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE atGeometry(Noise, geom) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE minusGeometry(Trip, geom) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE minusGeometry(Noise, geom) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE atStbox(Trip, stbox(geom)) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE atStbox(Noise, stbox(geom)) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE minusStbox(Trip, stbox(geom)) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE minusStbox(Noise, stbox(geom)) IS NOT NULL;

/* A2 - Distance / nearest approach */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE geom |=| Trip IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE geom |=| Noise IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE nearestApproachInstant(geom, Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE nearestApproachInstant(geom, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE shortestLine(geom, Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE shortestLine(geom, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE ST_Centroid(geom) <-> Trip IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE ST_Centroid(geom) <-> Noise IS NOT NULL;

/* A3 - Existential / always spatial relations */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eContains(geom, Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eContains(geom, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aContains(geom, Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aContains(geom, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eCovers(geom, Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eCovers(geom, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aCovers(geom, Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aCovers(geom, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eDisjoint(geom, Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eDisjoint(geom, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aDisjoint(geom, Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aDisjoint(geom, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eDwithin(geom, Trip, 100);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eDwithin(geom, Noise, 100);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aDwithin(geom, Trip, 100);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aDwithin(geom, Noise, 100);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eIntersects(geom, Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eIntersects(geom, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aIntersects(geom, Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aIntersects(geom, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eTouches(geom, Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE eTouches(geom, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aTouches(geom, Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE aTouches(geom, Noise);

/* A4 - Temporal-output spatial relations */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tIntersects(geom, Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tIntersects(geom, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tDisjoint(geom, Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tDisjoint(geom, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tContains(geom, Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tContains(geom, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tCovers(geom, Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tCovers(geom, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tDwithin(geom, Trip, 100) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tDwithin(geom, Noise, 100) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tTouches(geom, Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE tTouches(geom, Noise) IS NOT NULL;

/*****************************************************************************
 * Section B - Trip x cbuffer (tcbuffer only)
 *
 * Requires NaturalAreasCb100 to be present. The loader builds it as
 *   CREATE TABLE NaturalAreasCb100 AS
 *     SELECT Id, cbuffer(Geom) AS cb FROM NaturalAreas ORDER BY Id LIMIT 100;
 *****************************************************************************/

/* B1 - Restriction by cbuffer / stbox */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE atValue(Noise, cb) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE minusValue(Noise, cb) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE atStbox(Noise, stbox(cb)) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE minusStbox(Noise, stbox(cb)) IS NOT NULL;

/* B2 - Distance / nearest approach */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE cb |=| Noise IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE nearestApproachInstant(cb, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE shortestLine(cb, Noise) IS NOT NULL;

/* B3 - Existential / always spatial relations */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE eContains(cb, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE aContains(cb, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE eCovers(cb, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE aCovers(cb, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE eDisjoint(cb, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE aDisjoint(cb, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE eDwithin(cb, Noise, 100);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE aDwithin(cb, Noise, 100);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE eIntersects(cb, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE aIntersects(cb, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE eTouches(cb, Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE aTouches(cb, Noise);

/* B4 - Temporal-output spatial relations */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE tIntersects(cb, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE tDisjoint(cb, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE tContains(cb, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE tCovers(cb, Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreasCb100 t2
WHERE tDwithin(cb, Noise, 100) IS NOT NULL;

/*****************************************************************************
 * Section C - Trip x Trip: tgeompoint vs tcbuffer
 *****************************************************************************/

/* C1 - Temporal equality */

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE t1.Trip ?= t2.Trip IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE t1.Noise ?= t2.Noise IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE t1.Trip %= t2.Trip IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE t1.Noise %= t2.Noise IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE t1.Trip #= t2.Trip IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE t1.Noise #= t2.Noise IS NOT NULL;

/* C2 - Distance / nearest approach */

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE t1.Trip |=| t2.Trip IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE t1.Noise |=| t2.Noise IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE nearestApproachInstant(t1.Trip, t2.Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE nearestApproachInstant(t1.Noise, t2.Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE shortestLine(t1.Trip, t2.Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE shortestLine(t1.Noise, t2.Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE t1.Trip <-> t2.Trip IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE t1.Noise <-> t2.Noise IS NOT NULL;

/* C3 - Existential / always spatial relations */

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE eDisjoint(t1.Trip, t2.Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE eDisjoint(t1.Noise, t2.Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE aDisjoint(t1.Trip, t2.Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE aDisjoint(t1.Noise, t2.Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE eDwithin(t1.Trip, t2.Trip, 100);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE eDwithin(t1.Noise, t2.Noise, 100);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE aDwithin(t1.Trip, t2.Trip, 100);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE aDwithin(t1.Noise, t2.Noise, 100);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE eIntersects(t1.Trip, t2.Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE eIntersects(t1.Noise, t2.Noise);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE aIntersects(t1.Trip, t2.Trip);

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE aIntersects(t1.Noise, t2.Noise);

/* C4 - Temporal-output spatial relations */

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE tIntersects(t1.Trip, t2.Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE tIntersects(t1.Noise, t2.Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE tDisjoint(t1.Trip, t2.Trip) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE tDisjoint(t1.Noise, t2.Noise) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE tDwithin(t1.Trip, t2.Trip, 100) IS NOT NULL;

SELECT COUNT(*)
FROM VesselTrip100 t1, VesselTrip100 t2
WHERE tDwithin(t1.Noise, t2.Noise, 100) IS NOT NULL;

/* C5 - Aggregated set x set minimum distance.  For every vessel, the
   spatial minimum distance to every other vessel, ignoring time.  This is
   the BerlinMOD Q5 shape: a 2-ary minDistance aggregate over the
   cross-join grouped by the anchor vessel.  Equivalent to ST_Distance
   over the union of each vessel's footprint on each side. */

SELECT count(d) FROM (
  SELECT minDistance(t1.Trip, t2.Trip) AS d
  FROM VesselTrip100 t1, VesselTrip100 t2
  WHERE t1.mmsi <> t2.mmsi
  GROUP BY t1.mmsi
) x;

SELECT count(d) FROM (
  SELECT minDistance(t1.Noise, t2.Noise) AS d
  FROM VesselTrip100 t1, VesselTrip100 t2
  WHERE t1.mmsi <> t2.mmsi
  GROUP BY t1.mmsi
) x;

/*****************************************************************************
 * Section D - Expressiveness showcase: cumulative noise vs centerline
 *
 * The vessel centerline (Trip::tgeompoint) sails clear of the protected
 * areas. The underwater noise (Noise::tcbuffer) propagates beyond the
 * centerline and reaches some of them. The three queries below quantify
 * that gap with the cumulative footprint of each model.
 *****************************************************************************/

/* D1 - Protected areas reached by the centerline footprint */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE ST_Intersects(trajectory(t1.Trip), t2.geom);

/* D2 - Protected areas reached by the noise footprint */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE ST_Intersects(traversedArea(t1.Noise), t2.geom);

/* D3 - Gap: areas reached by noise that the centerline never enters */

SELECT COUNT(*)
FROM VesselTrip100 t1, NaturalAreas100 t2
WHERE ST_Intersects(traversedArea(t1.Noise), t2.geom)
  AND NOT ST_Intersects(trajectory(t1.Trip), t2.geom);

/*****************************************************************************/
