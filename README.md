# Une approche de reconstruction automatique de la géométrie des bureaux de vote

Script de reconstruction des géométries de bureau de vote depuis les adresses des électeurs.

Utilise une approche basée sur des diagrammes de Voronoï sous contraintes des limites de la voirie. Les géométries des bureaux sont ensuite complétés par des zones environnantes sans adresses.

![](bureaux.png)

## Import des adresses des électeurs

En utilisant le jeu de données [Bureaux de vote et adresses de leurs électeurs ](https://www.data.gouv.fr/fr/datasets/bureaux-de-vote-et-adresses-de-leurs-electeurs/) de l'INSEE.

```
curl https://www.data.gouv.fr/fr/datasets/r/5142e8a9-15f3-4216-b865-deeeb02dde70 | gzip > table-adresses-reu.csv.gz
```

```
psql -c "
CREATE TABLE dep(code_commune_ref varchar,reconstitution_code_commune varchar,id_brut_bv_reu varchar,id varchar,geo_adresse varchar,geo_type varchar,geo_score decimal,longitude float,latitude float,api_line varchar,nb_bv_commune integer,nb_adresses integer);"

zcat table-adresses-reu.csv.gz | psql -c "COPY dep(code_commune_ref,reconstitution_code_commune,id_brut_bv_reu,id,geo_adresse,geo_type,geo_score,longitude,latitude,api_line,nb_bv_commune,nb_adresses) FROM STDIN WITH CSV HEADER"
```

## Import des limites de communes

```
# 228 Mo
wget https://www.data.gouv.fr/fr/datasets/r/0e117c06-248f-45e5-8945-0e79d9136165 -O communes-20220101-shp.7z
unzip communes-20220101-shp.zip
shp2pgsql communes-20220101.shp | psql
```

## Import des données de voirie d’OpenStreetMap

À l'aide de [imposm3](https://imposm.org/).
```
# 3.5 Go
wget http://download.openstreetmap.fr/extracts/merge/france_metro_dom_com_nc-latest.osm.pbf
imposm import -mapping imposm.yaml -read france_metro_dom_com_nc-latest.osm.pbf -overwritecache -write -connection postgis://fred@localhost/fred
```

## Exécution des scripts de traitement

```
psql -v ON_ERROR_STOP=1 -f 10_communes.sql
psql -v ON_ERROR_STOP=1 -f 20_addresses.sql
psql -v ON_ERROR_STOP=1 -f 30_blocks.sql
psql -v ON_ERROR_STOP=1 -f 40_voronoi.sql
psql -v ON_ERROR_STOP=1 -f 50_bureau.sql
psql -v ON_ERROR_STOP=1 -f 60_block2.sql
psql -v ON_ERROR_STOP=1 -f 70_fill.sql
psql -v ON_ERROR_STOP=1 -f 80_clean.sql
psql -v ON_ERROR_STOP=1 -f 90_total.sql
```

## Export

### Conversion en PMTiles

```
docker run -it --rm -v /tmp:/data tippecanoe:latest \
    tippecanoe \
        -Z8 \
        -z14 \
        --attribution "INSEE REU 2022 - OpenStreetMap 2023" \
        /data/bureau.fgb \
        -o /data/bureau.pmtiles
```
