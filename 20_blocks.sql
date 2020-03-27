DROP TABLE IF EXISTS _blocks_separators CASCADE;
CREATE TABLE _blocks_separators AS
SELECT
    ST_Transform(geometry, 2154) AS geom
FROM
    import.osm_ways
WHERE
    tunnel = '' OR ST_Length(ST_Transform(geometry, 2154)) < 100
;
CREATE INDEX _blocks_separators_idx ON _blocks_separators USING gist(geom);


-- Drop small water area
DROP TABLE IF EXISTS _blocks_waters CASCADE;
CREATE TABLE _blocks_waters AS
SELECT
    geom
FROM (
    SELECT
        (ST_Dump(
            ST_Transform(ST_Union(geometry), 2154)
        )).geom AS geom
    FROM
        import.osm_polygons
) AS t
WHERE
    ST_Area(geom) > 10000
;


-- Remove water from communes
DROP TABLE IF EXISTS _blocks_communes CASCADE;
CREATE TABLE _blocks_communes AS
SELECT
    insee,
    ST_Difference(
        geom,
        (SELECT ST_Collect(geom) FROM _blocks_waters)
    ) AS geom
FROM
    communes
WHERE
    insee LIKE '94%'
GROUP BY
    insee,
    geom
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
