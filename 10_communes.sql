DROP TABLE IF EXISTS communes CASCADE;
CREATE TABLE communes AS
SELECT
    insee,
    nom,
    ST_Transform(ST_SetSRID(geom, 4326), 2154) AS geom
FROM
    "communes-20160119"
WHERE
    ST_GeometryType(geom) IN ('ST_Polygon', 'ST_MultiPolygon')
;
CREATE INDEX communes_idx ON communes USING gist(geom);
CREATE INDEX communes_insee_idx ON communes(insee);
