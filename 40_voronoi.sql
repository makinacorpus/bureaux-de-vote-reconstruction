-- Voronoi of addresse point limited by he block

DROP TABLE IF EXISTS _voronoi_geom CASCADE;
CREATE TABLE _voronoi_geom AS

-- Keep block with only one address
-- ST_VoronoiPolygons does not apply when there is only one point
SELECT
    blocks.id AS block_id,
    blocks.geom
FROM
     addresses
    JOIN blocks ON
        ST_Intersects( addresses.geom, blocks.geom)
WHERE
     addresses.geom IS NOT NULL
GROUP BY
    blocks.id,
    blocks.geom
HAVING
    count(*) = 1

UNION ALL

-- Voronoi
SELECT
    blocks.id AS block_id,
    (ST_Dump(ST_VoronoiPolygons(ST_Collect( addresses.geom), 0, blocks.geom))).geom AS geom
FROM
     addresses
    JOIN blocks ON
        ST_Intersects( addresses.geom, blocks.geom)
WHERE
     addresses.geom IS NOT NULL
GROUP BY
    blocks.id,
    blocks.geom
;


-- Join voronoi cell to original address point
DROP TABLE IF EXISTS _voronoi_plus CASCADE;
CREATE TABLE _voronoi_plus AS
SELECT
     addresses.insee,
    bureau,
    block_id,
    _voronoi_geom.geom
FROM
    _voronoi_geom
    JOIN blocks ON
        blocks.id = _voronoi_geom.block_id
    JOIN  addresses ON
        ST_Intersects( addresses.geom, blocks.geom) AND
        ST_Intersects( addresses.geom, _voronoi_geom.geom)
;
CREATE INDEX _voronoi_plus_idx ON _voronoi_plus(block_id);
CREATE INDEX _voronoi_plus_idx_ ON _voronoi_plus USING gist(geom);


-- Mutate isolated cell on block to be the same as neiborought
DROP TABLE IF EXISTS _voronoi_mutation CASCADE;
CREATE TABLE _voronoi_mutation AS
SELECT
    b1.insee,
    CASE
        WHEN min(b2.geom) IS NULL THEN b1.bureau
        WHEN count(DISTINCT b2.bureau) = 1 AND count(b2.bureau) >= 2 THEN min(b2.bureau) -- Switch to neiborought
        ELSE b1.bureau
    END AS bureau,
    b1.block_id,
    b1.geom
FROM
    _voronoi_plus AS b1
    LEFT JOIN _voronoi_plus AS b2 ON
        b1.block_id = b2.block_id AND
        NOT ST_Equals(b1.geom, b2.geom) AND
        ST_Touches(b1.geom, b2.geom)
GROUP BY
    b1.insee,
    b1.bureau,
    b1.block_id,
    b1.geom
;

-- TODO Mutate isolated polygon after cell unions (on block, or not) to be the same as neiborought


DROP VIEW IF EXISTS voronoi;
CREATE VIEW voronoi AS
SELECT * FROM _voronoi_mutation;


-------------------------------------------------------------------------
-- View only

-- DROP TABLE IF EXISTS _voronoi_mutation_view CASCADE;
-- CREATE TABLE _voronoi_mutation_view AS
-- SELECT
--     _voronoi_mutation.insee,
--     _voronoi_mutation.bureau,
--     _voronoi_mutation.block_id,
--     ST_Intersection(
--         _voronoi_mutation.geom,
--         (SELECT geom FROM blocks WHERE blocks.id = _voronoi_mutation.block_id)
--     ) AS geom
-- FROM
--     _voronoi_mutation
-- ;
