-- -----------------------------------------------------------------------------
-- Classify vessel activity based on whether the current and next positions
-- are inside a port area.
--
-- Activity codes:
-- 0 = inside the port
-- 1 = exiting the port
-- 2 = entering the port
-- 4 = sailing 
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS determineActivity;
CREATE FUNCTION determineActivity(    
  InPort      boolean,
  InPortNext  boolean
)
RETURNS INTEGER
LANGUAGE sql
AS $$
  SELECT
  CASE 
    WHEN (InPort AND NOT InPortNext) THEN 1
    WHEN (NOT InPort AND InPortNext) THEN 2 
    WHEN InPort THEN 0
    ELSE 4
  END;
$$;


-- -----------------------------------------------------------------------------
-- Return the reference class speed (Vc) based on vessel macro-category and
-- cargo classification.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ComputeVc;
CREATE FUNCTION ComputeVc(
  VesselClassCode  integer,
  ShipTypeCode     integer,
  SpeedKnots       double precision, 
  LOA              double precision
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
  CASE
    WHEN VesselClassCode = 1  THEN 10.6
    WHEN VesselClassCode = 2  THEN 6.4
    WHEN VesselClassCode = 3  THEN 3.7
    WHEN VesselClassCode = 4  THEN 9.5
    WHEN VesselClassCode = 5  THEN 11.1
    WHEN VesselClassCode = 6  THEN 8.0
    WHEN VesselClassCode = 7  THEN       
      CASE WHEN (LOA > 100) THEN 17.1 ELSE 9.7 END
    WHEN VesselClassCode = 9  THEN
      CASE
        WHEN (ShipTypeCode = 70 OR ShipTypeCode BETWEEN 75 AND 79) AND
          SpeedKnots <= 16 THEN 13.9   -- Bulker
        ELSE 18.0   -- Containership
      END
    WHEN VesselClassCode = 10 THEN 12.4
    WHEN VesselClassCode = 11 THEN 7.4
    ELSE NULL
  END;
$$;


-- -----------------------------------------------------------------------------
-- Compute the Source Level (SL) following the model of
-- MacGillivray & de Jong for vessel underwater radiated noise.
--
-- Inputs:
--   VesselClassCode   : vessel macro-category
--   f                 : frequency (Hz)
--   Vref              : vessel speed (knots)
--   Vc                : reference class speed (knots)
--   LOAref            : vessel length overall (metres)
--   InPort            : whether the vessel is located inside a port
--
-- Output:
--   SL (dB re 1 µPa @ 1 m)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS ComputeSL;
CREATE FUNCTION ComputeSL(
  VesselClassCode  integer,           -- 9 = cargo, 10 = tanker, 7 = cruise
  f                real,              -- frequency (Hz)
  Vref             double precision,  -- vessel speed (knots)
  Vc               double precision,  -- class reference speed (knots)
  LOAref           double precision,  -- vessel length (metres)
  InPort           boolean            -- whether the vessel is located inside a port
)
RETURNS DOUBLE PRECISION
LANGUAGE plpgsql
AS $$
DECLARE
  -- Vessel class flags
  isRecreational boolean :=        (VesselClassCode = 1);
  isFishing boolean :=             (VesselClassCode = 2);
  isTug boolean :=                 (VesselClassCode = 3);
  isDredger boolean :=             (VesselClassCode = 4);
  isNaval boolean :=               (VesselClassCode = 5);
  isGovernmentResearch boolean :=  (VesselClassCode = 6);
  isCruise boolean :=              (VesselClassCode = 7);
  isCargo boolean :=               (VesselClassCode = 9);
  isTanker boolean :=              (VesselClassCode = 10);
  isOther boolean :=               (VesselClassCode = 11);

  -- Model parameters
  K  DOUBLE PRECISION;
  B  DOUBLE PRECISION;
  f1 DOUBLE PRECISION;
  D  DOUBLE PRECISION;

  -- Intermediate terms of the analytical formulation
  term1 DOUBLE PRECISION;
  term2 DOUBLE PRECISION;
  term3 DOUBLE PRECISION;
  term4 DOUBLE PRECISION;
  term5 DOUBLE PRECISION;
  term6 DOUBLE PRECISION;

  SL DOUBLE PRECISION;

  -- Preserve the original speed for low-speed port correction
  Speed DOUBLE PRECISION := Vref;

BEGIN
  -- Parameter K
  IF f < 100 AND (isCargo OR isTanker) THEN K := 208;
  ELSE K := 191;
  END IF;

  -- Parameter B
  IF f < 100 AND (isCargo OR isTanker) THEN B := 2;
  ELSE B := 0;
  END IF;

  -- Characteristic frequency f1
  IF f < 100 AND (isCargo OR isTanker) THEN f1 := 600.0/Vc;
  ELSE f1 := 480.0/Vc;
  END IF;

  -- Parameter D
  IF f < 100 AND isCargo THEN D := 0.8;
  ELSIF f < 100 AND isTanker THEN D := 1.0;
  ELSIF isCruise THEN D := 4.0;
  ELSE D := 3.0;
  END IF;

  -- MacGillivray & de Jong source level formulation
  term1 := K - 10.0 * (B + 2.0) * LOG10(f1); 
  term2 :=  5.0 * B * LOG10(f);
  term3 := -10.0 * LOG10(POWER(1.0 - POWER(f/f1, 0.5*(B+2)), 2) + POWER(D,2));

  -- Enforce minimum modelling speed of 3 knots
  IF Vref < 3 THEN Vref:=3;
  END IF;

  term4 := 60.0 * LOG10(Vref / Vc);
  term5 := 20.0 * LOG10(LOAref / 91.44);  -- 91.44 m = reference LOA
  term6 := 10.0 * LOG10(0.231 * f);

  SL := term1 + term2 + term3 + term4 + term5 + term6;

  -- Empirical correction for vessels idling inside ports
  IF isCruise OR isCargo OR isTanker THEN
    IF InPort AND Speed < 0.5 THEN 
      SL := SL - 15;   -- subtract 15 dB
    END IF;
  END IF;

  RETURN SL;
END;
$$;

-- -----------------------------------------------------------------------------
-- Load the input files Port, SeaCells, NaturalAreas, and AISInput, where
-- the latter contains several days of AIS data input from the directory data/ 
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS tcbuffer_input;
CREATE FUNCTION tcbuffer_input(SF integer DEFAULT 1)
RETURNS void LANGUAGE plpgsql STRICT AS $$
DECLARE
  tableSize text;
  tableCount text;
  filePath text = :'data_dir';
  -- set with: psql -v data_dir=/path/to/aisdk-and-areas/
  fileName text;
  fileNames text[];
BEGIN
  CREATE EXTENSION IF NOT EXISTS mobilitydb CASCADE;

  SET TIMEZONE TO 'UTC';
  SET DATESTYLE TO 'ISO, DMY';

  RAISE INFO '--------------------------------------------------------------';
  RAISE INFO 'Loading input files...';
  RAISE INFO '--------------------------------------------------------------';

  RAISE INFO 'Creating table Port';
  DROP TABLE IF EXISTS Port;
  CREATE TABLE Port (
    Id        integer PRIMARY KEY,
    PortId    varchar(5) NOT NULL,
    DataSrc   bigint,
    PortCoor  varchar(1),
    CntrCode  varchar(2),
    PortName  varchar(100),
    RepMarL   varchar(50),
    Source    varchar(50),
    Traffic   integer,
    Geom      geometry(Polygon,25832)
  );
  EXECUTE format(
    'COPY Port (id, PortId, DataSrc, PortCoor, CntrCode, PortName, RepMarL, Source, Traffic, Geom)
      FROM %L WITH (FORMAT csv, HEADER true, DELIMITER '','')',
    filePath || 'port.csv'
  );

  RAISE INFO 'Creating table SeaCells';
  DROP TABLE IF EXISTS SeaCells;
  CREATE TABLE SeaCells (
    Id            bigint PRIMARY KEY,
    Longitude     double precision,
    Latitude      double precision,
    Depth         double precision,
    Alpha         double precision,
    AmbientNoise  double precision,
    Geom          geometry(Polygon,25832)
  );
  EXECUTE format(
    'COPY SeaCells (Id, Longitude, Latitude, Depth, Alpha, AmbientNoise, Geom)
      FROM %L WITH (FORMAT csv, HEADER true, DELIMITER '','')',
    filePath || 'sea_cells.csv'
  );

  RAISE INFO 'Creating table NaturalAreas';
  DROP TABLE IF EXISTS NaturalAreas CASCADE;
  CREATE TABLE NaturalAreas (
    Id integer PRIMARY KEY,
    SiteId integer,
    SitePid varchar(52),
    SiteType varchar(80),
    NameEng varchar(80),
    Name varchar(80),
    Desig varchar(80),
    DesigEng varchar(80),
    DesigType varchar(80),
    IucnCat varchar(80),
    IntCrit varchar(80),
    Realm varchar(20),
    RepMArea numeric,
    GisMArea numeric,
    RepArea numeric,
    GisArea numeric,
    NoTake varchar(80),
    NoTkArea numeric,
    Status varchar(80),
    StatusYr integer,
    GovType varchar(80),
    GovSubType varchar(80),
    OwnType varchar(80),
    OwnSubType varchar(80),
    MangAuth varchar(169),
    MangPlan varchar(169),
    Verif varchar(80),
    Metadataid integer,
    PrntISO3 varchar(80),
    ISO3 varchar(80),
    SuppInfo varchar(80),
    ConsObj varchar(80),
    InlndWtrs varchar(80),
    OecmAsmt varchar(80),
    Geom geometry(MultiPolygon,25832)
  );
  EXECUTE format(
    'COPY NaturalAreas (Id, SiteId, SitePid, SiteType, NameEng, Name, Desig, DesigEng, DesigType, IucnCat, 
      IntCrit, Realm, RepMArea, GisMArea, RepArea, GisArea, NoTake, NoTkArea, Status, StatusYr, GovType, 
      GovSubType, OwnType, OwnSubType, MangAuth, MangPlan, Verif, Metadataid, PrntISO3, ISO3, SuppInfo, 
      ConsObj, InlndWtrs, OecmAsmt, Geom)
      FROM %L WITH (FORMAT csv, HEADER true, DELIMITER '','')',
    filePath || 'natural_areas.csv'
  );

  CREATE INDEX IF NOT EXISTS PortGeomGix ON Port USING GIST (Geom);
  CREATE INDEX IF NOT EXISTS SeaCellGeomGix ON SeaCells USING GIST (Geom);
  CREATE INDEX IF NOT EXISTS NaturalAreasGeomGist ON NaturalAreas USING GIST (Geom);

  RAISE INFO 'Creating table AISInput';
  -- Create the table that stores the CSV files
  DROP TABLE IF EXISTS AISInput;
  CREATE TABLE AISInput (
    T timestamp,
    TypeOfMobile varchar(100),
    MMSI integer,
    Latitude float,
    Longitude float,
    NavigationalStatus varchar(100),
    ROT float,
    SOG float,
    COG float,
    Heading integer,
    IMO varchar(100),
    CallSign varchar(100),
    Name varchar(100),
    ShipType varchar(100),
    CargoType varchar(100),
    Width float,
    Length float,
    TypeOfPositionFixingDevice varchar(100),
    Draught float,
    Destination varchar(100),
    ETA varchar(100),
    DataSourceType varchar(100),
    SizeA float,
    SizeB float,
    SizeC float,
    SizeD float
  );

  -- Input the CSV files (retrieve file list from the directory in filePath)
  EXECUTE format(
    $q$
      SELECT array_agg(f ORDER BY f)
      FROM (
        SELECT f
        FROM pg_ls_dir(%L) AS f
        WHERE f ~* '.*\.csv$'   -- case-insensitive regex
        ORDER BY f
        LIMIT %s
      ) s
    $q$,
    filePath,
    SF
  )
  INTO fileNames;
  FOREACH fileName IN ARRAY fileNames
  LOOP
    RAISE INFO '  Inserting %', fileName;
    EXECUTE format(
      'COPY AISInput(T, TypeOfMobile, MMSI, Latitude, Longitude,'
      'NavigationalStatus,ROT, SOG, COG, Heading, IMO, CallSign, Name,'
      'ShipType, CargoType, Width, Length,TypeOfPositionFixingDevice,'
      'Draught, Destination, ETA, DataSourceType,SizeA, SizeB, SizeC, SizeD)'
      'FROM %L WITH DELIMITER '','' CSV HEADER', filePath || fileName);
  END LOOP;

  /* Create table AISInputFiltered that performs minimal data cleaning:
     * Filter out duplicate timestamps and invalid or out-of-range values of
       latitude and longitude
     * Create point geometry 
     * Set to NULL 'undefined' values appearing in various columns */
  RAISE INFO 'Creating table AISInputFiltered ...';
  DROP TABLE IF EXISTS AISInputFiltered;
  CREATE TABLE AISInputFiltered(T, TypeOfMobile, MMSI,
    NavigationalStatus, ROT, SOG, COG, Heading, IMO, CallSign, Name, ShipType,
    CargoType, Width, Length, TypeOfPositionFixingDevice, Draught,
    Destination, ETA, DataSourceType, SizeA, SizeB, SizeC, SizeD, Geom) AS
  SELECT DISTINCT ON (MMSI,T) T, TypeOfMobile, MMSI,
    CASE WHEN NavigationalStatus = 'Unknown value' THEN NULL ELSE NavigationalStatus END,
    ROT, SOG, COG, Heading, 
    CASE WHEN IMO = 'Unknown' THEN NULL ELSE IMO END,
    CASE WHEN CallSign = 'Unknown' THEN NULL ELSE CallSign END,
    Name,
    CASE WHEN ShipType = 'Undefined' OR ShipType = 'Other' THEN NULL ELSE ShipType END,
    CASE WHEN CargoType = 'No additional information' THEN NULL ELSE CargoType END,
    Width, Length,
    CASE WHEN TypeOfPositionFixingDevice = 'Undefined' THEN NULL ELSE TypeOfPositionFixingDevice END,
    Draught,
    CASE WHEN Destination ILIKE 'Unknown' THEN NULL ELSE Destination END,
    ETA, DataSourceType, SizeA, SizeB, SizeC, SizeD,
    ST_SetSRID(ST_MakePoint(Longitude, Latitude), 4326)
  FROM AISInput
  WHERE Longitude BETWEEN -16.1 AND 32.88 AND Latitude BETWEEN 40.18 AND 84.17
  ORDER BY MMSI, T;

  -- Create table with only the columns used for creating temporal types
  RAISE INFO 'Creating table AISInputTarget ...';
  DROP TABLE IF EXISTS AISInputTarget;
  CREATE TABLE AISInputTarget AS
  SELECT MMSI, IMO, Name, ShipType, CargoType, Length, T,
    SOG, COG, ST_Transform(Geom,25832) AS Geom
 FROM AISInputFiltered;

  -- Print statistics about the tables
  RAISE INFO '--------------------------------------------------------------';
  SELECT pg_size_pretty(pg_total_relation_size('AISInput')) INTO tableSize;
  SELECT to_char(COUNT(*), 'fm999G999G999') FROM AISInput INTO tableCount;
  RAISE INFO 'Size of the AISInput table: %, % rows', tableSize, tableCount;
  --
  SELECT pg_size_pretty(pg_total_relation_size('AISInputFiltered')) INTO tableSize;
  SELECT to_char(COUNT(*), 'fm999G999G999') FROM AISInputFiltered INTO tableCount;
  RAISE INFO 'Size of the AISInputFiltered table: %, % rows', tableSize, tableCount;
  --
  SELECT pg_size_pretty(pg_total_relation_size('AISInputTarget')) INTO tableSize;
  SELECT to_char(COUNT(*), 'fm999G999G999') FROM AISInputTarget INTO tableCount;
  RAISE INFO 'Size of the AISInputTarget table: %, % rows', tableSize, tableCount;
  RAISE INFO '--------------------------------------------------------------';

  RETURN;
END;
$$;

-- -----------------------------------------------------------------------------
-- Reconstruct trajectories from AIS data and prepares the main derived tables:
--   - Vessel (vessel with type codes)
--   - VesselPoint (points with derived speed/activity/SL and trip_id)
--   - VesselTrip (MobilityDB temporal types and trajectory geometry)
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS tcbuffer_trajectories;
CREATE FUNCTION tcbuffer_trajectories()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  tableSize text;
  tableCount text;
BEGIN
  RAISE INFO '--------------------------------------------------------------';
  RAISE INFO 'Reconstructing vessel trajectories...';
  RAISE INFO '--------------------------------------------------------------';

  RAISE INFO 'Creating the Vessel table ...';
  -- Build the Vessel table from the table AISInputTarget
  DROP TABLE IF EXISTS Vessel;
  CREATE TABLE Vessel (
    -- MMSI (Maritime Mobile Service Identity)
    MMSI bigint PRIMARY KEY,  
    -- Name of the vessel as reported in AIS messages
    Name text,                
    -- Length of the vessel in metres
    Length double precision,  
    -- Textual label of the AIS vessel type (e.g., Cargo, Fishing, Passenger)
    ShipTypeLabel text,       
    -- Numeric code associated with the AIS vessel type (standard AIS codes, 
    -- e.g., 70 for Cargo, 30 for Fishing)
    ShipTypeCode smallint,    
    -- Code representing a higher-level vessel category (e.g., Sailing and
    -- Pleasure are classified as Recreational vessels)
    VesselClassCode smallint  
  );

  INSERT INTO Vessel (MMSI,Name,Length,ShipTypeLabel,ShipTypeCode,
    VesselClassCode)
  WITH Temp1 (MMSI,Name,Length,ShipTypeLabel,ShipTypeCode) AS (
  SELECT DISTINCT ON (MMSI) MMSI,Name,Length,ShipType,
    CASE ShipType
      WHEN 'Pilot'            THEN 50
      WHEN 'SAR'              THEN 51
      WHEN 'Tug'              THEN 52
      WHEN 'Port tender'      THEN 53
      WHEN 'Anti-pollution'   THEN 54
      WHEN 'Law enforcement'  THEN 55
      WHEN 'Fishing'          THEN 30
      WHEN 'Towing'           THEN 31
      WHEN 'Towing long/wide' THEN 32
      WHEN 'Dredging'         THEN 33
      WHEN 'Diving'           THEN 34
      WHEN 'Military'         THEN 35
      WHEN 'Sailing'          THEN 36
      WHEN 'Pleasure'         THEN 37
      WHEN 'HSC'              THEN 40
      WHEN 'Passenger'        THEN 60
      WHEN 'Cargo'            THEN 70
      WHEN 'Tanker'           THEN 80
      WHEN 'Other'            THEN 90
      ELSE NULL
    END
  FROM AISInputTarget
  WHERE Length > 0 AND ShipType NOT IN ( 'Undefined','Spare 1','Spare 2',
    'Reserved','WIG','Not party to conflict' )
  ),
  Temp2 (MMSI,Name,Length,ShipTypeLabel,ShipTypeCode,VesselClassCode) AS (
    SELECT t.*, 
      CASE ShipTypeCode
        -- Tug & port services
        WHEN 50 THEN 3  -- Pilot  -> tug-ish / service 
        WHEN 51 THEN 6  -- SAR    -> government/research
        WHEN 52 THEN 3  -- Tug    -> tug
        WHEN 53 THEN 3  -- Port tender -> tug/service
        WHEN 54 THEN 11 -- Anti-pollution -> other
        WHEN 55 THEN 6  -- Law enforcement -> government/research
        -- Fishing / workboats
        WHEN 30 THEN 2  -- Fishing -> fishing
        WHEN 31 THEN 3  -- Towing  -> tug
        WHEN 32 THEN 3  -- Towing
        WHEN 33 THEN 4  -- Dredging -> dredger 
        WHEN 34 THEN 11 -- Diving -> other
        WHEN 35 THEN 5  -- Military -> naval
        WHEN 36 THEN 1  -- Sailing  -> recreational
        WHEN 37 THEN 1  -- Pleasure -> recreational
        -- HSC / passenger
        WHEN 40 THEN 7  -- HSC -> passenger/cruise; 
        WHEN 60 THEN 7  -- Passenger -> passenger/cruise
        -- Merchant
        WHEN 70 THEN 9  -- Cargo -> cargo
        WHEN 80 THEN 10 -- Tanker -> tanker
        WHEN 90 THEN 11 -- Other -> other
        ELSE NULL
      END
    FROM Temp1 t 
  )
  SELECT *
  FROM Temp2
  WHERE ShipTypeCode IS NOT NULL AND VesselClassCode IS NOT NULL
  ORDER BY MMSI;

  RAISE INFO 'Creating the VesselPointRaw table ...';
  -- Add to the AISInputTarget table information about vessels
  DROP TABLE IF EXISTS VesselPointRaw;
  CREATE UNLOGGED TABLE VesselPointRaw AS
  SELECT a.MMSI,a.ShipType,a.CargoType,v.Length,a.T AS DateTime,
    a.SOG,a.COG,Geom,v.ShipTypeCode,v.VesselClassCode
  FROM AISInputTarget a, Vessel v
  -- Keep only validated vessel having a valid SOG
  WHERE a.MMSI = v.MMSI AND SOG <= 50;

  -- SELECT 7074229
  -- Time: 15423.852 ms (00:15.424)

  CREATE INDEX VesselPointRawGeomGistIdx ON VesselPointRaw USING GIST (Geom);

  RAISE INFO 'Creating the VesselPointCell table ...';
  /* Add to the VesselPointRaw table information about
    - the grid cell to which the point belongs
    - whether the point is inside a port or not */
  DROP TABLE IF EXISTS VesselPointCell;
  CREATE UNLOGGED TABLE VesselPointCell (
    MMSI bigint,
    DateTime timestamptz,
    GridId bigint,
    AmbientNoise real, 
    Depth double precision,
    SOG double precision,
    VesselLength double precision,
    ShipTypeCode smallint,
    VesselClassCode smallint,
    CargoType text,
    Geom geometry(Point,25832),
    InPort boolean
  );

  INSERT INTO VesselPointCell(MMSI,DateTime,GridId,AmbientNoise,Depth,
    SOG,VesselLength,ShipTypeCode,VesselClassCode,CargoType,Geom,InPort)
  WITH
  -- Keep only points that fall within a grid cell and add cell information
  VesselPointWithCell AS (
    SELECT a.MMSI,DateTime,c.Id AS GridId,c.AmbientNoise,c.Depth,
      a.SOG,Length AS VesselLength,a.ShipTypeCode,VesselClassCode,
      a.CargoType,a.Geom
    FROM VesselPointRaw a, SeaCells c
    WHERE c.Geom && a.Geom AND ST_Intersects(c.Geom, a.Geom)
  ),
  -- Add the inPort flag that is true if the point falls within a port area
  VesselPointCellPort AS (
    SELECT s.*,
      EXISTS (
        SELECT 1
        FROM Port p
        WHERE p.Geom && s.Geom AND ST_Intersects(p.Geom, s.Geom)
      ) AS InPort
    FROM VesselPointWithCell s
  ),
  /* Remove points of vessels that are not passenger/cruise, cargo, or
     tanker (ShipTypeCode not between 60 and 89) when they are inside a
     port area and moving at very low speed (< 0.5 knots), as these points
     likely correspond to moored vessels that continue transmitting AIS data
     even when their engines are off. */
  Filtered AS (
    SELECT *
    FROM VesselPointCellPort
    WHERE NOT ( InPort = true AND SOG < 0.5 AND 
      -- 60-69 cruise and passenger, 70-79 cargo, 80-89 tanker
      ShipTypeCode NOT BETWEEN 60 AND 89 ) 
  )
  -- Remove duplicates when a point is at the border of two grid cells
  SELECT DISTINCT ON (MMSI, DateTime) * FROM Filtered;

  -- INSERT 0 4860911
  -- Time: 201532.160 ms (03:21.532)

  RAISE INFO 'Deleting the VesselPointRaw table ...';
  DROP TABLE VesselPointRaw;

  RAISE INFO 'Creating the VesselPointSpeed table ...';
  -- Add to the VesselPointCell table information about the speed and the
  -- activity of the vessel 
  DROP TABLE IF EXISTS VesselPointSpeed;
  CREATE UNLOGGED TABLE VesselPointSpeed(
    MMSI bigint,
    DateTime timestamptz,
    GridId bigint,
    AmbientNoise real, 
    Depth double precision,
    Geom geometry(Point,25832),
    InPort boolean,
    DurationFromPrevPoint interval,
    Speed double precision,
    Activity integer,
    SL double precision
  )
  WITH (
    autovacuum_enabled = false,
    toast.autovacuum_enabled = false
  );

  INSERT INTO VesselPointSpeed(MMSI,DateTime,GridId,AmbientNoise,Depth,
      Geom,InPort,DurationFromPrevPoint,Speed,Activity,SL)
  WITH PointActivity(MMSI,DateTime,GridId,AmbientNoise,Depth,VesselLength,
      ShipTypeCode,VesselClassCode,CargoType,Geom,InPort,
      DurationFromPrevPoint,Speed,Activity) AS ( 
    SELECT MMSI,DateTime,GridId,AmbientNoise,Depth,VesselLength,
      ShipTypeCode,VesselClassCode,CargoType,Geom,InPort,
      (DateTime - LAG(DateTime) OVER w),
      CASE
        -- To avoid division by zero or zero-speed cases,
        -- we assign a velocity value close to zero in these situations.
        WHEN SOG IS NULL OR abs(SOG) < 1e-8 THEN 1e-8
        -- Set to 40 knots all points with SOG greater than 40 knots
        WHEN SOG > 40 THEN 40
        ELSE SOG
      END,
      DetermineActivity(InPort,LEAD(InPort) OVER w)
    FROM VesselPointCell
    WINDOW w AS (PARTITION BY MMSI ORDER BY MMSI, DateTime)
    ORDER BY MMSI,DateTime
  ),
  PointVcKnots AS ( 
    SELECT *,
      computeVc(VesselClassCode,ShipTypeCode,Speed,VesselLength) AS VcKnots
    FROM PointActivity
  )
  SELECT MMSI,DateTime,GridId,AmbientNoise,Depth,
    Geom,InPort,DurationFromPrevPoint,Speed,Activity,
    ComputeSL(VesselClassCode,63.0,Speed,VcKnots,VesselLength,InPort)
  FROM PointVcKnots
  ORDER BY MMSI, DateTime;

  -- INSERT 0 4860911
  -- Time: 64818.596 ms (01:04.819)

  RAISE INFO 'Deleting the VesselPointCell table ...';
  DROP TABLE VesselPointCell;

  RAISE INFO 'Creating the VesselPoint table ...';
  /* Add to the table VesselPointSpeed a Trip identifier where a new trip
     starts when
     -- (1) a vessel stayed in port longer than threshold
     -- (2) a vessel exits port after a long temporal gap */
  DROP TABLE IF EXISTS VesselPoint;
  CREATE TABLE VesselPoint(
    TripId integer,
    MMSI bigint NOT NULL,
    DateTime timestamptz,
    GridId bigint,
    AmbientNoise real, 
    Depth double precision,
    Geom geometry(Point,25832),
    InPort boolean,
    Speed real,
    Activity integer,
    SL double precision
  )
  WITH (
    autovacuum_enabled = false,
    toast.autovacuum_enabled = false
  );

  INSERT INTO VesselPoint(TripId,MMSI,DateTime,GridId,AmbientNoise,Depth,
    Geom,InPort,Speed,Activity,SL)
  WITH Params(Threshold, LongGap) AS (
    SELECT interval '9 minutes', interval '20 minutes' ),
  TripsOrdered AS (
    SELECT *, LAG(InPort) OVER w AS PrevInPort
    FROM VesselPointSpeed
    WINDOW w AS (PARTITION BY MMSI ORDER BY DateTime)
  ),
  TripFlags AS (
    SELECT *,
      CASE
        -- (1) vessel stayed in port longer than threshold
        WHEN InPort = TRUE 
            AND DurationFromPrevPoint > Threshold THEN 1
        -- (2) vessel exits port after a long temporal gap
        WHEN PrevInPort = TRUE AND InPort = FALSE
            AND DurationFromPrevPoint > LongGap THEN 1
        ELSE 0
      END AS NewTrip
    FROM TripsOrdered, Params
  ),
  TripNumbers AS (
    SELECT SUM(NewTrip) OVER w + 1 AS TripId, *
    FROM TripFlags
    WINDOW w AS (PARTITION BY MMSI ORDER BY DateTime ROWS UNBOUNDED PRECEDING)
  ),
  Trips AS (
    SELECT TripId,MMSI,DateTime,GridId,AmbientNoise,Depth,Geom,InPort,
      Speed,Activity,SL, COUNT(*) OVER (PARTITION BY TripId) AS NoPoints
    FROM TripNumbers 
  )
  -- Remove trips that contain 10 or fewer points
  SELECT TripId,MMSI,DateTime,GridId,AmbientNoise,Depth,Geom,InPort,
    Speed,Activity,SL
  FROM Trips
  WHERE NoPoints > 10
  ORDER BY MMSI, DateTime;

  -- INSERT 0 4855910
  -- Time: 47109.800 ms (00:47.110)

  RAISE INFO 'Deleting the VesselPointSpeed table ...';
  DROP TABLE IF EXISTS VesselPointSpeed;

  RAISE INFO 'Creating the VesselTrip table ...';
  -- Construct the vessel trip table
  DROP TABLE IF EXISTS VesselTrip CASCADE;
  CREATE TABLE VesselTrip (
    TripId integer,
    MMSI bigint,
    InPort tbool,
    Radius tfloat,
    Speed tfloat,
    SL tfloat,
    Activity tint,
    Trip tgeompoint,
    Anomaly integer,
    Trajectory geometry,
    Noise tcbuffer,
    TraversedArea geometry,
    PRIMARY KEY(TripId, MMSI)
  );

  INSERT INTO VesselTrip(TripId,MMSI,InPort,Radius,Speed,SL,Activity,Trip,
    Anomaly,Trajectory,Noise,TraversedArea)
  WITH AmbientNoise(TripId,MMSI,DateTime,InPort,Radius,Speed,
      SL,Activity,Geom) AS (
    SELECT TripId,MMSI,DateTime,InPort,
      -- Mode-stripping propagation
      -- POWER(10, (SL - 5 * LOG10(10 * Depth) - AmbientNoise) / 15.),
      -- Spherical propagation
      POWER(10, (SL - AmbientNoise) / 20.) AS Radius,
      Speed,SL,Activity,Geom
    FROM VesselPoint 
  ),
  VesselTemp(TripId,MMSI,InPort,Radius,Speed,SL,Activity,Trip) AS (
    SELECT TripId,MMSI,
      tboolSeqSetGaps(array_agg(tbool(InPort,DateTime) 
        ORDER BY DateTime),'30 minutes'::interval),   
      -- Limit the radius at 10000 m = 10 km
      tfloatSeqSetGaps(array_agg(tfloat(CASE WHEN Radius > 10000
        THEN 10000 ELSE Radius END,DateTime) 
        ORDER BY DateTime),'30 minutes'::interval),
      tfloatSeqSetGaps(array_agg(tfloat(CASE WHEN Speed IS NOT NULL
        THEN Speed ELSE 0 END, DateTime)
        ORDER BY DateTime),'30 minutes'::interval),
      tfloatSeqSetGaps(array_agg(tfloat(sl, DateTime)
        ORDER BY DateTime),'30 minutes'::interval),
      tintSeqSetGaps(array_agg(tint(Activity,DateTime)
        ORDER BY DateTime),'30 minutes'::interval),
      tgeompointSeqSetGaps(array_agg(tgeompoint(Geom,DateTime)
        ORDER BY DateTime),'30 minutes'::interval)
    FROM AmbientNoise
    WHERE Radius IS NOT NULL
    GROUP BY TripId,MMSI
  ),
  VesselNoise AS (
    SELECT TripId,MMSI,InPort,Radius,Speed,SL,Activity,Trip,
      CASE
        WHEN InPort %= true THEN 2
        WHEN duration(Trip) > interval '24 hours' AND NumSeqs > 1 THEN 4
        WHEN duration(Trip) > interval '24 hours' THEN 3
        WHEN NumSeqs > 1 THEN 1
        ELSE 0
      END AS Anomaly,
      trajectory(Trip) AS Trajectory, tcbuffer(Trip, Radius) AS Noise
    FROM ( SELECT *, numSequences(Trip) AS NumSeqs FROM VesselTemp ) t
  )
  SELECT TripId,MMSI,InPort,Radius,Speed,SL,Activity,Trip,Anomaly,
    Trajectory,Noise, NULL -- TraversedArea(Noise)
  FROM VesselNoise
  ORDER BY TripId,MMSI;

  -- INSERT 0 2111
  -- Time: 68701.119 ms (01:08.701)
  
  UPDATE VesselTrip SET TraversedArea = TraversedArea(Noise);

  CREATE INDEX IF NOT EXISTS VesselTripTripIdx ON VesselTrip USING GIST(Trip);
  CREATE INDEX IF NOT EXISTS VesselTripNoiseIdx ON VesselTrip USING GIST(Noise);
  
  -- UPDATE 2111
  -- Time: 443995.806 ms (07:23.996)

  -- Print statistics about the tables
  RAISE INFO '--------------------------------------------------------------';
  SELECT pg_size_pretty(pg_total_relation_size('Vessel')) INTO tableSize;
  SELECT to_char(COUNT(*), 'fm999G999G999') FROM Vessel INTO tableCount;
  RAISE INFO 'Size of the Vessel table: %, % rows', tableSize, tableCount;
  -- 
  SELECT pg_size_pretty(pg_total_relation_size('VesselPoint')) INTO tableSize;
  SELECT to_char(COUNT(*), 'fm999G999G999') FROM VesselPoint INTO tableCount;
  RAISE INFO 'Size of the VesselPoint table: %, % rows', tableSize, tableCount;
  -- 
  SELECT pg_size_pretty(pg_total_relation_size('VesselTrip')) INTO tableSize;
  SELECT to_char(COUNT(*), 'fm999G999G999') FROM VesselTrip INTO tableCount;
  RAISE INFO 'Size of the VesselTrip table: %, % rows', tableSize, tableCount;
  RAISE INFO '--------------------------------------------------------------';

  RETURN;
END;
$$;


-- -----------------------------------------------------------------------------
-- Master funcion to execute the complete underwater-noise processing pipeline.
--
-- Execution order:
--   1. Load static input datasets (ports and sea grid)
--   2. Reconstruct trajectories from AIS data
--
-- This script is intended to be executed via psql:
--   psql -d <database> -f tcbuffer_run_all.sql
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS tcbuffer_load;
CREATE FUNCTION tcbuffer_load(SF integer DEFAULT 1)
RETURNS void LANGUAGE plpgsql STRICT AS $$
DECLARE
  start_time timestamptz;
  end_time timestamptz;
  duration interval;
BEGIN

  SET TIMEZONE TO 'UTC';

  -- Store start time
  SELECT clock_timestamp() INTO start_time;

  PERFORM tcbuffer_input(SF);

  PERFORM tcbuffer_trajectories();

  -- Materialise the 100-row subsets used by tcbuffer_benchmark.sql
  RAISE INFO 'Creating the bench views VesselTrip100, NaturalAreas100, NaturalAreasCb100 ...';
  DROP VIEW IF EXISTS VesselTrip100;
  CREATE VIEW VesselTrip100 AS
    SELECT * FROM VesselTrip ORDER BY TripId LIMIT 100;
  DROP VIEW IF EXISTS NaturalAreas100;
  CREATE VIEW NaturalAreas100 AS
    SELECT * FROM NaturalAreas ORDER BY Id LIMIT 100;
  DROP TABLE IF EXISTS NaturalAreasCb100;
  CREATE TABLE NaturalAreasCb100 AS
    SELECT Id, cbuffer(Geom) AS cb FROM NaturalAreas ORDER BY Id LIMIT 100;

  -- Store end time and compute elapsed time
  SELECT clock_timestamp() INTO end_time;
  SELECT end_time - start_time INTO duration;
      
  RAISE INFO '--------------------------------------------------------------';
  RAISE INFO 'Pipeline completed successfully.';
  RAISE INFO 'Start time: %', to_char(start_time, 'YYYY-MM-DD HH24:MI:SS');
  RAISE INFO 'End time: %', to_char(end_time,   'YYYY-MM-DD HH24:MI:SS');
  RAISE INFO 'Duration: %', to_char(duration,   'HH24:MI:SS');
  RAISE INFO '--------------------------------------------------------------';

  RETURN;
END;
$$;

-------------------------------------------------------------------------------