require 'csv'
require 'yaml'
require 'json'

ontology_json = ARGV[0]
layer_yaml = ARGV[1]
mapping_yaml = ARGV[2]
class_sql = ARGV[3]
ontology = JSON.parse(File.new(ontology_json).read)

osm_tags_extra = ontology['osm_tags_extra']

osm_tags = ontology['superclass'].values.collect{ |superclass|
  (superclass['class'] || {}).values.collect{ |classs|
    (classs['subclass'] || {}).values.collect{ |subclass|
      subclass['osm_tags']
    } + [classs['osm_tags'] || []]
  } + [[superclass['osm_tags'] || []]]
}.flatten.compact.collect(&:to_a).flatten(1).uniq.select{ |k, _| k[-1] != '!' }.group_by{ |k, _| k }.transform_values{ |values| values.collect{ |_, v| v }.sort - ['*'] }.select{ |k, v| v.size > 0 }

osm_tags['leisure'] = ['__any__']
osm_tags['landuse'] = ['__any__']

y = { 'def_poi': Hash[osm_tags] }
yaml_str = YAML.dump(y)

include_tags = (osm_tags.keys + osm_tags_extra).sort.uniq.join("', '")
include_tags = "'#{include_tags}'" if include_tags.size > 0

poi_yaml = File.open(layer_yaml).read
poi_yaml = YAML::load(poi_yaml)

query = '(SELECT osm_id, geometry, name, name_en, name_de, {name_languages}, superclass, class, subclass, zoom, priority, style, agg_stop, layer, level, indoor, rank, {extra_attributes} FROM layer_poi_tourism(!bbox!, z(!scale_denominator!), !pixel_width!)) AS t'
query = query.gsub('{extra_attributes}', osm_tags_extra.map{ |t| "tags->'#{t}' AS \"#{t}\"" }.join(', '))
poi_yaml['layer']['datasource']['query'] = query

keep_fields = %w[geometry name name_en name_de superclass class subclass zoom priority style agg_stop layer level indoor rank]
poi_yaml['layer']['fields'] = poi_yaml['layer']['fields'].slice(*keep_fields).merge(Hash[osm_tags_extra.map{ |t| [t, nil] }])
File.open(layer_yaml, 'w').write(YAML::dump(poi_yaml))

file = File.open(mapping_yaml, 'w')
file.write("""
tags:
  include: [#{include_tags}]
#{yaml_str.gsub('def_poi:', 'def_poi: &poi_mapping').gsub('---', '')}

def_poi_fields: &poi_fields
  - name: osm_id
    type: id
  - name: geometry
    type: geometry
  - name: name
    key: name
    type: string
  - name: name_en
    key: name:en
    type: string
  - name: name_de
    key: name:de
    type: string
  - name: tags
    type: hstore_tags
  - name: subclass
    type: mapping_value
  - name: mapping_key
    type: mapping_key
  - name: station
    key: station
    type: string
  - name: funicular
    key: funicular
    type: string
  - name: information
    key: information
    type: string
  - name: uic_ref
    key: uic_ref
    type: string
  - name: religion
    key: religion
    type: string
  - name: level
    key: level
    type: integer
  - name: indoor
    key: indoor
    type: bool
  - name: layer
    key: layer
    type: integer
  - name: sport
    key: sport
    type: string
  - name: access -- for reject filters
    key: access
    type: string

tables:
  # etldoc: imposm3 -> osm_poi_point
  poi_point:
    type: point
    columns: *poi_fields
    mapping: *poi_mapping
    filters:
      reject:
        access: ['no']

  # etldoc: imposm3 -> osm_poi_polygon
  poi_polygon:
    type: polygon
    columns: *poi_fields
    mapping: *poi_mapping
    filters:
      reject:
        access: ['no']
""")


whens = ontology['superclass'].collect{ |k_super, superclass|
  (superclass['class'] || {}).collect{ |k, classs|
    (classs['subclass'] || {}).collect{ |k_sub, subclass|
      [k_super, k, k_sub, subclass['zoom'], subclass['style'], subclass['priority'], subclass['osm_tags']]
    } + (classs['style'] ? [[k_super, k, nil, classs['zoom'], classs['style'], classs['priority'], classs['osm_tags']]] : [])
  }
}.flatten(2).sort.collect{ |superclass, classs, subclass, zoom, style, priority, osm_tags|
  superclass = "'#{superclass}'"
  classs = "'#{classs}'"
  subclass = subclass ? "'#{subclass}'" : 'NULL'
  zoom ||= 18
  style = style && style != '' ? "'#{style}'" : 'NULL'

  tags = osm_tags[0].collect{ |k, v|
    if ['*', nil].include?(v)
      "(tags?'#{k}' AND tags->'#{k}' != 'no')"
    else
      negative = k[-1] == '!'
      k = k[0..-2] if negative
      values = (v || '').split(';').map{ |t| "'#{t}'" }
      if negative
        if values.size == 1
          "(NOT tags?'#{k}' OR tags->'#{k}' != #{values[0]})"
        else
          "(NOT tags?'#{k}' OR tags->'#{k}' NOT IN (#{values.join(', ')}))"
        end
      else
        if values.size == 1
          "tags?'#{k}' AND tags->'#{k}' = #{values[0]}"
        else
          "tags?'#{k}' AND tags->'#{k}' IN (#{values.join(', ')})"
        end
      end
    end
  }.join(' AND ')

  if superclass == "'remarkable'" && classs == "'attraction_activity'" && subclass == "'attraction'"
    "(SELECT
  #{superclass}, #{classs}, #{subclass},
  CASE
    WHEN score >= 11 THEN 13
    WHEN score >= 5 THEN 14
    ELSE 17
  END AS zoom,
  '⬤' AS style,
  CASE
    WHEN score >= 11 THEN 0
    WHEN score >= 8 THEN 50
    ELSE 100
  END AS priority
FROM (
  SELECT
    CASE tags->'heritage' WHEN '1' THEN 10 WHEN '2' THEN 5 WHEN '3' THEN 2 ELSE 1 END +
    CASE WHEN tags ?& ARRAY['wikipedia', 'wikidata'] THEN 5 ELSE 0 END +
    CASE WHEN tags?'name' THEN 1 ELSE 0 END +
    CASE WHEN tags ?& ARRAY['website', 'phone', 'email', 'opening_hours'] THEN 1 ELSE 0 END AS score
  WHERE #{tags}
) AS score)"
  else
    "            SELECT #{superclass}, #{classs}, #{subclass}, #{zoom}, #{style}, #{priority} WHERE #{tags}"
  end
}.join(" UNION ALL\n")

file = File.open(class_sql, 'w')
file.write("""
CREATE OR REPLACE FUNCTION poi_tourismclasss(key TEXT, value TEXT, tags hstore) RETURNS TABLE (
    superclass TEXT,
    class TEXT,
    subclass TEXT,
    zoom INTEGER,
    style TEXT,
    priority INTEGER
) AS $$
    SELECT * FROM (
#{whens}
    ) AS t(superclass, class, subclass, zoom, style, priority)
    ORDER BY
        zoom,
        priority
    LIMIT 1
$$
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE;
""")
