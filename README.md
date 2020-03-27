# Une approche de la reconstruction automatique de la géométrie des bureaux de vote

Script de reconstruction des géométries de bureau de vote depuis les adresses des électeurs.

Utilise une approche basée sur des diagrammes de Voronoï sous contraintes des limites de la voirie. Les géométries des bureaux sont ensuite complétés par des zones environnantes sans adresses.

![](bureaux.png)

## Import des adresses

```
psql -c "
CREATE TABLE dep(bureau varchar, adresse  varchar, cp  varchar, ville  varchar, latitude  varchar, longitude  varchar, result_label  varchar, result_score  varchar, result_type  varchar, result_id  varchar, result_housenumber  varchar, result_name  varchar, result_street  varchar, result_postcode  varchar, result_city  varchar, result_context  varchar, result_citycode varchar);"

bzcat dep.csv.bz2 | psql -c "COPY dep(bureau,adresse,cp,ville,latitude,longitude,result_label,result_score,result_type,result_id,result_housenumber,result_name,result_street,result_postcode,result_city,result_context,result_citycode) FROM STDIN WITH CSV HEADER"
```

## Import des limites de communes

```
# 228 Mo
wget https://www.data.gouv.fr/fr/datasets/r/63f720c7-d4d2-49f1-bdbc-4a7ac58c10fd
unzip communes-20160119-shp.zip
php2pgsql communes-20160119.shp | psql
```

## Import des données de voirie d’OpenStreetMap

```
# 28 Mo
wget http://download.openstreetmap.fr/extracts/europe/france/ile_de_france/val_de_marne-latest.osm.pbf
imposm import -mapping imposm.yaml -read val_de_marne-latest.osm.pbf -overwritecache -write -connection postgis://fred@localhost/fred
```

## Exécution des scripts de traitement

```
psql < 10_communes.sql
20_blocks.sql
psql -v ON_ERROR_STOP=1 
30_addresses.sql
40_voronoi.sql
50_bureau.sql
60_block2.sql
70_fill.sql
80_clean.sql
```
