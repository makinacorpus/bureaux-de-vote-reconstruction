DROP TABLE IF EXISTS _clean_buffer CASCADE;
CREATE TABLE _clean_buffer AS
SELECT
    insee,
    bureau,
    block_ids,
    ST_Buffer(
        ST_Buffer(
            geom,
            1,
            'join=mitre mitre_limit=2'
        ),
        -1,
        'join=mitre mitre_limit=2'
    ) AS geom
FROM
    fill
;
