CREATE OR REPLACE FUNCTION PolygonNPoints(poly geometry)
RETURNS integer AS $$
    SELECT
        count(*)::integer
    FROM(
        SELECT
            (ST_DumpPoints(poly))
    ) AS t
$$ LANGUAGE sql IMMUTABLE;


CREATE OR REPLACE FUNCTION _fill_join_free_blocks(contraint integer)
RETURNS void AS $$
BEGIN
    -- Get the bureau geom the most simple by the addition of the free block.
    -- The shape should be more regural after the addition af the free block.
    RAISE NOTICE '_fill_blocks_bureau';
    DROP TABLE IF EXISTS _fill_blocks_bureau CASCADE;
    CREATE TABLE _fill_blocks_bureau AS
    SELECT DISTINCT ON (_fill_free_blocks.id)
        _fill_free_blocks.id AS block_id,
        _fill_free_blocks.geom AS block_geom,
        bureau.insee,
        bureau.bureau,
        bureau.block_ids,
        bureau.geom AS bureau_geom,
        bureau.geom_limit
    FROM
       _fill_free_blocks
        -- blocks2 AS _fill_free_blocks
        JOIN _fill_bureau AS bureau ON
            bureau.insee = _fill_free_blocks.insee AND
            --ST_Intersects(bureau.geom, _fill_free_blocks.geom) AND
            bureau.geom && _fill_free_blocks.geom AND
            ST_Contains(bureau.geom_limit, _fill_free_blocks.geom) AND
            ( -- Avoid only touch by one point
                ST_Area(ST_Intersection(
                    _fill_free_blocks.geom,
                    ST_MakeValid(ST_Buffer(bureau.geom, .1, 'join=mitre mitre_limit=2'))
                )) > .1
                OR -- Or geometry is smaller than the test buffer
                ST_Area(ST_Intersection(
                    _fill_free_blocks.geom,
                    ST_MakeValid(ST_Buffer(bureau.geom, .1, 'join=mitre mitre_limit=2'))
                )) > 0.9 * ST_Area(_fill_free_blocks.geom)
            )
    WHERE
        ST_NumGeometries(ST_Buffer(ST_Collect(_fill_free_blocks.geom, bureau.geom), 1, 'join=mitre mitre_limit=2'))
        <
        ST_NumGeometries(ST_MakeValid(ST_Buffer(bureau.geom, 1, 'join=mitre mitre_limit=2')))
        OR
        -- Diff of point number of geometry after block simplified union with bureau
        -- Less point is more simple shape
        -- Simpler shape have negative diff.
        (
            -- Buffer help to remove silder gap polygon, counting as points
            PolygonNPoints(ST_Simplify(ST_Buffer(ST_Collect(_fill_free_blocks.geom, bureau.geom), 1, 'join=mitre mitre_limit=2'), 1))
        -
            PolygonNPoints(ST_Simplify(ST_MakeValid(ST_Buffer(bureau.geom, 1, 'join=mitre mitre_limit=2')), 1))
        <= 2 + contraint
        )
    ORDER BY
        _fill_free_blocks.id,
        (
            ST_NumGeometries(ST_Buffer(ST_Collect(_fill_free_blocks.geom, bureau.geom), 1, 'join=mitre mitre_limit=2'))
        -
            ST_NumGeometries(ST_MakeValid(ST_Buffer(bureau.geom, 1, 'join=mitre mitre_limit=2')))
        ),

        (
            PolygonNPoints(ST_Simplify(ST_Buffer(ST_Collect(_fill_free_blocks.geom, bureau.geom), 1, 'join=mitre mitre_limit=2'), 1))
        -
            PolygonNPoints(ST_Simplify(ST_MakeValid(ST_Buffer(bureau.geom, 1, 'join=mitre mitre_limit=2')), 1))
        )
        -- ST_Length(ST_Intersection(_fill_free_blocks.geom, bureau.geom))
        -- ST_Area(ST_Intersection(
            -- _fill_free_blocks.geom,
            -- ST_Buffer(bureau.geom, .1, 'join=mitre mitre_limit=2')
        -- )) DESC,

        --ST_Length(ST_Intersection(_fill_free_blocks.geom, bureau.geom))
        -- ST_Area(ST_Intersection(
        --     _fill_free_blocks.geom,
        --     ST_Buffer(bureau.geom, .1, 'join=mitre mitre_limit=2')
        -- )) DESC

        -- ST_Area(ST_ConvexHull(bureau.geom))
        -- -
        -- ST_Area(ST_ConvexHull(ST_Buffer(ST_Collect(_fill_free_blocks.geom, bureau.geom), 1, 'join=mitre mitre_limit=2')))
    ;
    CREATE INDEX _fill_blocks_bureau_idx ON _fill_blocks_bureau(insee, bureau);

    -- Merge bureau with the better free blocks.
    -- Plus get back the bureau without free blocks.
    RAISE NOTICE '_fill_bureau_plus0';
    DROP TABLE IF EXISTS _fill_bureau_plus0 CASCADE;
    CREATE TABLE _fill_bureau_plus0 AS
    SELECT
        insee,
        bureau,
        block_ids || array_agg(block_id) AS block_ids,
        -- ST_CollectionExtract(ST_Union(bureau_geom, ST_Union(block_geom)), 3) AS geom,
        ST_Collect(block_geom) AS geom,
        bureau_geom,
        geom_limit
    FROM
        _fill_blocks_bureau
    GROUP BY
        insee,
        bureau,
        block_ids,
        bureau_geom,
        geom_limit
    ;

    RAISE NOTICE '_fill_bureau_plus';
    DROP TABLE IF EXISTS _fill_bureau_plus CASCADE;
    CREATE TABLE _fill_bureau_plus AS
    SELECT
        insee,
        bureau,
        block_ids,
        -- ST_CollectionExtract(ST_Union(bureau_geom, ST_Union(block_geom)), 3) AS geom,
        ST_CollectionExtract(ST_Buffer(ST_Collect(bureau_geom, geom), 0), 3) AS geom,
        geom_limit
    FROM
        _fill_bureau_plus0

    UNION ALL

    SELECT
        bureau.insee,
        bureau.bureau,
        bureau.block_ids,
        bureau.geom,
        bureau.geom_limit
    FROM
        _fill_bureau AS bureau
        LEFT JOIN _fill_blocks_bureau ON
            _fill_blocks_bureau.insee = bureau.insee AND
            _fill_blocks_bureau.bureau = bureau.bureau
    WHERE
        _fill_blocks_bureau.insee IS NULL
    ;

    DROP TABLE IF EXISTS _fill_bureau CASCADE;
    CREATE TABLE _fill_bureau AS
    SELECT * FROM _fill_bureau_plus;
    CREATE INDEX _fill_bureau_idx ON _fill_bureau USING gist(geom);
    CREATE INDEX _fill_bureau_idx_block_ids ON _fill_bureau USING gin(block_ids);


    -- Get blocks not part of any bureau
    RAISE NOTICE '_fill_free_blocks';
    DROP TABLE IF EXISTS _fill_free_blocks CASCADE;
    CREATE TABLE _fill_free_blocks AS
    SELECT
        blocks.insee,
        blocks.id,
        blocks.geom
    FROM
        blocks2 AS blocks
        LEFT JOIN _fill_bureau ON
            ARRAY[blocks.id] <@ _fill_bureau.block_ids
    WHERE
        _fill_bureau.block_ids IS NULL
    ;
    CREATE INDEX _fill_free_blocks_idx ON _fill_free_blocks USING gist(geom);
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION _fill_aggregate_free_blocks(nb_iter integer, constrain integer)
RETURNS void AS $$
DECLARE
   _count INTEGER;
   _count_old INTEGER;
   iter INTEGER := 1;
BEGIN
    _count_old := (SELECT count(*) from _fill_free_blocks);
    RAISE NOTICE 'Initial free block count %.', _count_old;

    LOOP
        PERFORM _fill_join_free_blocks((iter::float / nb_iter * constrain)::integer);

        _count := (SELECT count(*) from _fill_free_blocks);
        RAISE NOTICE '%/% New free block count %.', iter , nb_iter, _count;
        EXIT WHEN _count = _count_old OR iter >= nb_iter;
        _count_old := _count;
        iter := iter + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- Initialise before loop

DROP TABLE IF EXISTS _fill_bureau CASCADE;
CREATE TABLE _fill_bureau AS
SELECT
    insee,
    bureau,
    block_ids,
    geom,
    ST_Buffer(geom, 150) AS geom_limit
FROM
    bureau
;
CREATE INDEX _fill_bureau_idx ON _fill_bureau USING gist(geom);
CREATE INDEX _fill_bureau_idx_block_ids ON _fill_bureau USING gin(block_ids);


DROP TABLE IF EXISTS _fill_free_blocks CASCADE;
CREATE TABLE _fill_free_blocks AS
SELECT insee, id, geom FROM blocks2;
CREATE INDEX _fill_free_blocks_idx ON _fill_free_blocks USING gist(geom);


SELECT _fill_aggregate_free_blocks(5, 5);



DROP VIEW IF EXISTS fill CASCADE;
CREATE VIEW fill AS
SELECT * FROM _fill_bureau;
