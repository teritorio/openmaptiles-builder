#!/bin/bash

set -e

# Import DOC_TOURISM
source .env

curl -L "${DOC_TOURISM}/gviz/tq?tqx=out:csv&sheet=POI_liste_teritorio" > data-vectoriel-revu.csv
curl -L "${DOC_TOURISM}/gviz/tq?tqx=out:csv&sheet=Sous-Attributs" > data-vectoriel-revu-tags.csv

ruby ontology-build.rb data-vectoriel-revu.csv ontology.json
