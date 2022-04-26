#!/bin/bash

set -e

# Import DOC_TOURISM and DOC_CITY
source .env

# Tourism
curl -L "${DOC_TOURISM}/gviz/tq?tqx=out:csv&sheet=POI_liste_teritorio" > ontology-tourism.csv
curl -L "${DOC_TOURISM}/gviz/tq?tqx=out:csv&sheet=Sous-Attributs" > ontology-tourism-extra_tags.csv

ruby ontology-build.rb tourism 'Ontology Tourism' \
    ontology-tourism.csv \
    ontology-tourism-extra_tags.csv \
    ontology-tourism.json

# City
curl -L "${DOC_CITY}/gviz/tq?tqx=out:csv&sheet=POI_liste_teritorio" > ontology-city.csv
curl -L "${DOC_CITY}/gviz/tq?tqx=out:csv&sheet=Sous-Attributs" > ontology-city-extra_tags.csv

ruby ontology-build.rb city 'Ontology City' \
    ontology-city.csv \
    ontology-city-extra_tags.csv \
    ontology-city.json \
