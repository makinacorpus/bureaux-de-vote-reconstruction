-- Add continue end of street as more sperators


-- Get blocks not part of bureau
DROP TABLE IF EXISTS _blocks2_free_blocks CASCADE;
CREATE TABLE _blocks2_free_blocks AS
SELECT
    blocks.insee,
    blocks.id,
    blocks.geom
FROM
    blocks
    LEFT JOIN bureau ON
        blocks.id = ANY (bureau.block_ids)
WHERE
    bureau.block_ids IS NULL
;
CREATE INDEX _blocks2_free_blocks_idx ON _blocks2_free_blocks USING gist(geom);


-- Split linestring into segements
CREATE OR REPLACE FUNCTION segmentize_linestring(linestring geometry)
RETURNS geometry AS $$
    WITH
    p AS (
        SELECT
            (ST_DumpPoints(linestring)).path[1] AS path,
            (ST_DumpPoints(linestring)).geom
    ),
    pp AS (
        SELECT
            array_agg(geom) AS geom
        FROM
            p
    )
    SELECT
        ST_Collect(ST_MakeLine(geom[n], geom[n+1])) AS geom
    FROM
        pp,
        generate_series(1, ST_NPoints(linestring) - 1) AS s(n)
    ;
$$ LANGUAGE sql;


-- Split polygon into segements
CREATE OR REPLACE FUNCTION segmentize_polygon(poly geometry)
RETURNS geometry AS $$
    SELECT segmentize_linestring(ST_ExteriorRing((ST_DumpRings(poly)).geom));
$$ LANGUAGE sql;


-- Get segements from bureau poygons rings
DROP TABLE IF EXISTS _blocks2_bureau_segements;
CREATE TABLE _blocks2_bureau_segements AS
SELECT
    insee,
    bureau,
    (ST_Dump(segmentize_polygon(geom))).geom AS geom
FROM
    (SELECT insee, bureau, (ST_Dump(geom)).geom FROM bureau) AS t
;
CREATE INDEX _blocks2_bureau_segements_idx ON _blocks2_bureau_segements USING gist(geom);



DROP TABLE IF EXISTS _blocks2_free_blocks_buffer;
CREATE TABLE _blocks2_free_blocks_buffer AS
SELECT
    insee,
    id,
    (ST_Dump(ST_Buffer(ST_Collect(geom), 0.1, 'join=mitre mitre_limit=2'))).geom AS geom
FROM
    _blocks2_free_blocks
GROUP BY
    insee,
    id
;
CREATE INDEX _blocks2_free_blocks_buffer_idx ON _blocks2_free_blocks_buffer USING gist(geom);


-- Kepp only segement touching free block, but not coliear
DROP TABLE IF EXISTS _blocks2_bureau_segements_touch;
CREATE TABLE _blocks2_bureau_segements_touch AS
WITH
b AS (
    SELECT
        _blocks2_bureau_segements.*,
        a.id
    FROM
        _blocks2_bureau_segements
        JOIN _blocks2_free_blocks_buffer AS a ON
            a.insee = _blocks2_bureau_segements.insee AND
            ST_Intersects(a.geom, _blocks2_bureau_segements.geom)
)
SELECT
    b.insee,
    b.id,
    b.geom
FROM
    b
    LEFT JOIN _blocks2_free_blocks_buffer AS a ON
        ST_Contains(
            a.geom,
            b.geom
        )
WHERE
    a.geom IS NULL
;


CREATE OR REPLACE FUNCTION extend_linestring(line geometry, length numeric)
RETURNS geometry AS $$
DECLARE
    A geometry;
    B geometry;
    azimuth numeric;
BEGIN
    -- get the points A and B given a line L
    A := ST_STARTPOINT(line);
    B := ST_ENDPOINT(line);

    -- get the bearing from point B --> A
    azimuth := ST_AZIMUTH(B, A);

    -- create a new points far away from A and B
    RETURN ST_MakeLine(
        ST_TRANSLATE(A, sin(azimuth) * length, cos(azimuth) * length),
        ST_TRANSLATE(B, sin(azimuth) * -length, cos(azimuth) * -length)
    );
END;
$$ LANGUAGE plpgsql;


-- Extend both sides of the segments
DROP TABLE IF EXISTS _blocks2_ways_extends;
CREATE TABLE _blocks2_ways_extends AS
SELECT
    insee,
    id,
    extend_linestring(geom, 100) AS geom
FROM
    _blocks2_bureau_segements_touch
;
CREATE INDEX _blocks2_ways_extends_idx ON _blocks2_ways_extends USING gist(geom);


-- Split free blocks by segements from bureau
DROP TABLE IF EXISTS blocks2 CASCADE;
CREATE TABLE blocks2 AS
SELECT
    blocks.insee,
    nextval('blocks_id') AS id,
    (ST_Dump(ST_Split( -- Bug on ST_Plit, éfondre des géometries
        blocks.geom,
        ST_Union(_blocks2_ways_extends.geom)
    ))).geom AS geom
FROM
    _blocks2_free_blocks AS blocks
    JOIN _blocks2_ways_extends ON
        blocks.geom && _blocks2_ways_extends.geom --AND
        --blocks.id = _blocks2_ways_extends.id
GROUP BY
    blocks.insee,
    blocks.id,
    blocks.geom

UNION ALL

SELECT
    blocks.insee,
    blocks.id,
    blocks.geom
FROM
    _blocks2_free_blocks AS blocks
    LEFT JOIN _blocks2_ways_extends ON
        blocks.geom && _blocks2_ways_extends.geom --AND
        --blocks.id = _blocks2_ways_extends.id
WHERE
    _blocks2_ways_extends.geom IS NULL
;
CREATE INDEX blocks2_idx ON blocks2 USING gist(geom);
