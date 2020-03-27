-- Filter data quality and reporject
DROP TABLE IF EXISTS _addresses_dep2154 CASCADE;
CREATE TABLE _addresses_dep2154 AS
SELECT
    result_citycode AS insee,
    bureau,
    ST_Transform(ST_SetSRID(ST_MakePoint(longitude::float, latitude::float), 4326), 2154) AS geom
FROM
    dep
WHERE
    ville IS NOT NULL AND
    bureau IS NOT NULL AND
    result_type IN ('housenumber', 'locality') AND
    result_score::float > 0.7
;


-- Ensure geocoded points are in declared municipality
DROP TABLE IF EXISTS _addresses_insee CASCADE;
CREATE TABLE _addresses_insee AS
SELECT
    _addresses_dep2154.*
FROM
    _addresses_dep2154
    JOIN communes ON
        communes.insee = _addresses_dep2154.insee AND
        ST_Intersects(communes.geom, _addresses_dep2154.geom)
;

-- Make address point unique on better geoloc
DROP TABLE IF EXISTS _addresses_uniq CASCADE;
CREATE TABLE _addresses_uniq AS
WITH c AS (
SELECT
    insee,
    bureau,
    geom,
    count(*) AS count
FROM
    _addresses_insee
GROUP BY
    insee,
    bureau,
    geom
)
SELECT DISTINCT ON (geom)
    insee,
    bureau,
    geom
FROM
    c
ORDER BY
    geom,
    count,
    insee,
    bureau
;


DROP TABLE IF EXISTS addresses CASCADE;
CREATE TABLE addresses AS
WITH
median_point AS (
    SELECT
        insee,
        bureau,
        ST_GeometricMedian(ST_Collect(geom)) AS geom
    FROM
        _addresses_uniq
    GROUP BY
        insee,
        bureau
),
median_distance AS (
    SELECT
        insee,
        bureau,
        percentile_disc(.5) WITHIN GROUP (ORDER BY ST_Distance(_addresses_uniq.geom, median_point.geom)) AS median_distance,
        median_point.geom
    FROM
        _addresses_uniq
        JOIN median_point USING (insee, bureau)
    GROUP BY
        insee,
        bureau,
        median_point.geom
)
SELECT
    insee,
    bureau,
    _addresses_uniq.geom
FROM
    _addresses_uniq
    JOIN median_distance USING (insee, bureau)
WHERE
    ST_Distance(_addresses_uniq.geom, median_distance.geom) < 5 * median_distance.median_distance
;
CREATE INDEX addresses_idx ON addresses USING gist(geom);
