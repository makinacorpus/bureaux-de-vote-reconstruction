-- Keep the original block geometry when all call of the block are on the same bureau
-- rather than union of voronoi introducing computation error
DROP TABLE IF EXISTS _bureau_full_block CASCADE;
CREATE TABLE _bureau_full_block AS
SELECT
    blocks.insee,
    min(voronoi.bureau) AS bureau, -- On one bureau
    blocks.id AS block_id,
    blocks.geom
FROM
    blocks
    JOIN voronoi ON
        voronoi.block_id = blocks.id
GROUP BY
    blocks.insee,
    blocks.id,
    blocks.geom
HAVING
    count(DISTINCT voronoi.bureau) = 1
;


-- Get blocks with multiple bureau
DROP TABLE IF EXISTS _bureau_non_full_block CASCADE;
CREATE TABLE _bureau_non_full_block AS
SELECT
    blocks.id,
    blocks.geom
FROM
    blocks
    JOIN voronoi ON
        voronoi.block_id = blocks.id
GROUP BY
    blocks.insee,
    blocks.id,
    blocks.geom
HAVING
    count(DISTINCT voronoi.bureau) > 1
;


-- Union of cell by bureau and by block

-- DROP SEQUENCE _bureau_non_full_block_id;
-- CREATE SEQUENCE _bureau_non_full_block_id;

DROP TABLE IF EXISTS _bureau_non_full_block_union CASCADE;
CREATE TABLE _bureau_non_full_block_union AS
SELECT
    insee,
    bureau,
    _bureau_non_full_block.id AS block_id,
    -- nextval('_bureau_non_full_block_id') AS id,
--    ST_Buffer(ST_Collect(voronoi.geom), 0.1, 'join=mitre mitre_limit=2') AS geom
ST_Intersection(
        ST_Buffer(ST_Collect(voronoi.geom), 0),
    _bureau_non_full_block.geom
)
    AS geom
FROM
    voronoi
    JOIN _bureau_non_full_block ON
        _bureau_non_full_block.id = voronoi.block_id
GROUP BY
    insee,
    bureau,
    _bureau_non_full_block.id,
    _bureau_non_full_block.geom
;


DROP TABLE IF EXISTS _bureau_non_full_block_union CASCADE;
CREATE TABLE _bureau_non_full_block_union AS
SELECT
    insee,
    bureau,
    block_id,
    ST_Intersection(
        ST_Buffer(ST_Collect(voronoi.geom), 0),
        (SELECT geom FROM _bureau_non_full_block AS b WHERE b.id = voronoi.block_id)
    )
    AS geom
FROM
    voronoi
GROUP BY
    insee,
    bureau,
    block_id
;


DROP TABLE IF EXISTS _bureau_limit CASCADE;
CREATE TABLE _bureau_limit AS
SELECT
    insee,
    bureau,
    ST_Buffer(
        ST_ConcaveHull(
            ST_Collect(geom),
            0.99,
            false
        ),
        400,
        'join=mitre mitre_limit=2'
    ) AS geom
FROM
     addresses
GROUP BY
    insee,
    bureau
;


-- Union of all bureau part
DROP TABLE IF EXISTS _bureau_union CASCADE;
CREATE TABLE _bureau_union AS
SELECT
    insee,
    bureau,
    array_agg(block_id) AS block_ids,
    ST_CollectionExtract(
        ST_Intersection(
            ST_Union(geom),
            (SELECT geom FROM _bureau_limit AS b WHERE b.insee = t.insee AND b.bureau = t.bureau)
        ),
        3
    ) AS geom
FROM (
    SELECT insee, bureau, block_id, geom FROM _bureau_full_block UNION all
    SELECT insee, bureau, block_id, geom FROM _bureau_non_full_block_union
) AS t
GROUP BY
    insee,
    bureau
;
CREATE INDEX _bureau_union_idx ON _bureau_union USING gist(geom);


DROP VIEW IF EXISTS bureau CASCADE;
CREATE VIEW bureau AS
SELECT * FROM _bureau_union;
