DROP TABLE IF EXISTS _blocks_separators CASCADE;
CREATE TABLE _blocks_separators AS
WITH osm_ways AS (
    SELECT
        tunnel,
        ST_Transform(geometry, 2154) AS geometry
    FROM
        import.osm_ways
)
SELECT
    geometry AS geom
FROM
    osm_ways
    JOIN communes ON
        ST_Intersects(communes.geom, geometry)
    JOIN communes_multi_bureau ON
        communes_multi_bureau.insee = communes.insee
WHERE
    tunnel = '' OR ST_Length(geometry) < 100
GROUP BY
    geometry
;
CREATE INDEX _blocks_separators_idx ON _blocks_separators USING gist(geom);


-- Drop small water area
DROP TABLE IF EXISTS _blocks_waters CASCADE;
CREATE TABLE _blocks_waters AS
WITH
cluster AS(
    SELECT
        unnest(ST_ClusterIntersecting(geometry)) AS geometry
    FROM
        import.osm_polygons
),
polyunion AS (
    SELECT
        (ST_Dump(
            ST_Transform(ST_UnaryUnion(geometry), 2154)
        )).geom AS geom
    FROM
        cluster
)
SELECT
    ST_Subdivide(geom, 1024) AS geom
FROM
    polyunion
WHERE
    ST_Area(geom) > 10000
;
CREATE INDEX _blocks_waters_idx ON _blocks_waters USING gist(geom);


-- Remove water from communes
DROP TABLE IF EXISTS _blocks_communes CASCADE;
CREATE TABLE _blocks_communes AS
SELECT
    communes.insee,
    CASE
    WHEN ST_Collect(_blocks_waters.geom) IS NULL THEN communes.geom
    ELSE
        ST_Difference(
            communes.geom,
            ST_Collect(_blocks_waters.geom)
        )
    END AS geom
FROM
    communes
    JOIN communes_multi_bureau ON
        communes_multi_bureau.insee = communes.insee
    LEFT JOIN _blocks_waters ON
        _blocks_waters.geom && communes.geom
GROUP BY
    communes.insee,
    communes.geom
;


-- Split communes by separators
DROP SEQUENCE IF EXISTS blocks_id;
CREATE SEQUENCE blocks_id;

DROP TABLE IF EXISTS blocks CASCADE;
CREATE TABLE blocks AS
SELECT
    _blocks_communes.insee,
    nextval('blocks_id') AS id,
    (ST_Dump(ST_Split(
        _blocks_communes.geom,
        ST_Collect(_blocks_separators.geom)
    ))).geom AS geom
FROM
    _blocks_communes
    LEFT JOIN _blocks_separators ON
        _blocks_communes.geom && _blocks_separators.geom
GROUP BY
    _blocks_communes.insee,
    _blocks_communes.geom
;
CREATE INDEX blocks_idx ON blocks USING gist(geom);
