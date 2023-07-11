-- Fonction by chat GPT for "a function to convert color in hsl to rgb in pl/pgsql'
-- Fonction fixed manually
CREATE OR REPLACE FUNCTION hsl_to_rgb(hue FLOAT, saturation FLOAT, lightness FLOAT)
  RETURNS TEXT AS $$
DECLARE
  chroma FLOAT;
  hue_segment FLOAT;
  intermediate FLOAT;
  red FLOAT;
  green FLOAT;
  blue FLOAT;
  min_value FLOAT;
  red_hex TEXT;
  green_hex TEXT;
  blue_hex TEXT;
BEGIN
  IF saturation = 0 THEN
    -- HSL values are achromatic (grayscale)
    RETURN lpad(to_hex(round(lightness * 255)), 2, '0') || lpad(to_hex(round(lightness * 255)), 2, '0') || lpad(to_hex(round(lightness * 255)), 2, '0');
  ELSE
    IF lightness < 0.5 THEN
      chroma := (2 * lightness * saturation);
    ELSE
      chroma := ((2 - (2 * lightness)) * saturation);
    END IF;

    hue_segment := hue / 60.0;
    intermediate := chroma * (1 - ABS((hue_segment::decimal % 2) - 1));

    red := 0;
    green := 0;
    blue := 0;

    IF hue_segment >= 0 AND hue_segment <= 1 THEN
      red := chroma;
      green := intermediate;
    ELSIF hue_segment > 1 AND hue_segment <= 2 THEN
      red := intermediate;
      green := chroma;
    ELSIF hue_segment > 2 AND hue_segment <= 3 THEN
      green := chroma;
      blue := intermediate;
    ELSIF hue_segment > 3 AND hue_segment <= 4 THEN
      green := intermediate;
      blue := chroma;
    ELSIF hue_segment > 4 AND hue_segment <= 5 THEN
      red := intermediate;
      blue := chroma;
    ELSIF hue_segment > 5 AND hue_segment <= 6 THEN
      red := chroma;
      blue := intermediate;
    END IF;

    min_value := lightness - (chroma / 2);

    red_hex := lpad(to_hex(((red + min_value) * 255)::int), 2, '0');
    green_hex := lpad(to_hex(((green + min_value) * 255)::int), 2, '0');
    blue_hex := lpad(to_hex(((blue + min_value) * 255)::int), 2, '0');

    RETURN red_hex || green_hex || blue_hex;
  END IF;
END;
$$ LANGUAGE plpgsql;


DROP TABLE IF EXISTS bureau_total CASCADE;
CREATE TABLE bureau_total AS
WITH b AS (
    SELECT
        _clean_buffer.insee,
        nom,
        bureau,
        block_ids,
        _clean_buffer.geom
    FROM
        _clean_buffer
        JOIN communes ON
            communes.insee = _clean_buffer.insee

    UNION ALL

    SELECT
        communes.insee,
        nom,
        NULL,
        NULL,
        geom
    FROM
        communes
        LEFT JOIN communes_multi_bureau ON
            communes_multi_bureau.insee = communes.insee
    WHERE
        communes_multi_bureau.insee IS NULL
),
s AS (
    SELECT
        *,
        coalesce(
            ascii(substring(bureau from char_length(bureau) for 1)),
            replace(replace(insee, 'A', '11'), 'B', '12')::int
        ) AS salz
    FROM
        b
)
SELECT
    insee,
    nom,
    bureau,
    block_ids,
    ST_Transform(geom, 4326) AS geom,
    '#' || hsl_to_rgb(
        (replace(replace(insee, 'A', '11'), 'B', '12')::int + salz % 10) % 360,
        (40.0 + salz % 10 * 6) / 100,
        0.5
    ) AS color
FROM
    s
;
