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
CREATE INDEX _bureau_non_full_block_idx ON _bureau_non_full_block(id);
ALTER TABLE _bureau_non_full_block ADD PRIMARY KEY (id);


-- Union of cell by bureau and by block

DROP TABLE IF EXISTS _bureau_non_full_block_union CASCADE;
CREATE TABLE _bureau_non_full_block_union AS
WITH u AS (
    SELECT DISTINCT ON (insee, bureau, block_id, voronoi.geom)
        insee,
        bureau,
        block_id,
        voronoi.geom AS voronoi_geom,
        b.geom AS b_geom
    FROM
        voronoi
        JOIN _bureau_non_full_block AS b ON
            b.id = voronoi.block_id
    ORDER BY
        insee,
        bureau,
        block_id,
        voronoi.geom
)
SELECT
    insee,
    bureau,
    block_id,
    ST_Intersection(
        ST_Buffer(voronoi_geom, 0),
        b_geom
    )
    AS geom
FROM
    u
;


DROP TABLE IF EXISTS _bureau_limit CASCADE;
CREATE TABLE _bureau_limit AS
SELECT
    addresses.insee,
    bureau,
    ST_Buffer(
        ST_Envelope(
            ST_Collect(geom)
        ),
        400,
        'join=mitre mitre_limit=2'
    ) AS geom
FROM
    addresses
    JOIN communes_multi_bureau ON
        communes_multi_bureau.insee = addresses.insee
GROUP BY
    addresses.insee,
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
CREATE INDEX _bureau_union_idx_block_ids ON _bureau_union USING gin(block_ids);


DROP VIEW IF EXISTS bureau CASCADE;
CREATE VIEW bureau AS
SELECT * FROM _bureau_union;
