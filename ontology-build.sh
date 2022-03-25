#!/bin/bash

set -e

# Import DOC_TOURISM
source .env

curl -L "${DOC_TOURISM}/gviz/tq?tqx=out:csv&sheet=POI_liste_teritorio" > ontology-tourism.csv
curl -L "${DOC_TOURISM}/gviz/tq?tqx=out:csv&sheet=Sous-Attributs" > ontology-tourism-extra_tags.csv

ruby ontology-build.rb \
    ontology-tourism.csv \
    ontology-tourism-extra_tags.csv \
    ontology-tourism.json
