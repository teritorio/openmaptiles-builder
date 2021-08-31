#!/bin/bash

set -e

DOC=https://docs.google.com/spreadsheets/d/1ZuM75PCFAchGOfOLEC3DITuATJeqr3h6HEjZ7E8tA4o
#DOC=https://docs.google.com/spreadsheets/d/1qwkWacnw5Mz26tUuDU9AAfL5CMqjHoSw1aPRORXGZIM

curl -L "${DOC}/gviz/tq?tqx=out:csv&sheet=POI_liste_teritorio" > data-vectoriel-revu.csv
curl -L "${DOC}/gviz/tq?tqx=out:csv&sheet=Sous-Attributs" > data-vectoriel-revu-tags.csv

ruby a.rb data-vectoriel-revu.csv data-vectoriel-revu-tags.csv
