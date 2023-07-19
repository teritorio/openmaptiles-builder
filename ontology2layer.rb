require 'csv'
require 'yaml'
require 'json'

theme = ARGV[0]
ontology_json = ARGV[1]
layer_yaml = ARGV[2]
mapping_yaml = ARGV[3]
class_sql = ARGV[4]
class_java = ARGV[5]
ontology = JSON.parse(File.new(ontology_json).read)


class String
  def unquote
    s = self.dup

    case self[0,1]
    when "'", '"', '`'
      s[0] = ''
    end

    case self[-1,1]
    when "'", '"', '`'
      s[-1] = ''
    end

    return s
  end
end

osm_tags_extra = ontology['osm_tags_extra']

osm_tags = ontology['superclass'].values.collect{ |superclass|
  (superclass['class'] || {}).values.collect{ |classs|
    (classs['subclass'] || {}).values.collect{ |subclass|
      subclass['osm_tags']
    } + [classs['osm_tags'] || []]
  } + [[superclass['osm_tags'] || []]]
}.flatten.compact.collect{ |t|
  t[1..-2].split('][')
}.flatten.collect{ |t|
  t.split(/(=|~=|=~|!=|!~|~)/, 2).collect(&:unquote)
}.group_by(&:first).transform_values{ |v|
  v.collect{ |vv| vv[2] }.flatten.sort
}.select{ |k, v|
  v != []
}.to_h

osm_tags['leisure'] = ['__any__']
osm_tags['landuse'] = ['__any__']

y = { def_poi: osm_tags.to_h }
yaml_str = YAML.dump(y)

include_tags = (osm_tags.keys + osm_tags_extra).sort.uniq.join("', '")
include_tags = "'#{include_tags}'" if include_tags.size > 0

poi_yaml = File.read(layer_yaml)
poi_yaml = YAML.load(poi_yaml)

query = "(SELECT osm_id, geometry, name, name_en, name_de, {name_languages}, superclass, class, subclass, zoom, priority, style, agg_stop, layer, level, indoor, rank, {extra_attributes} FROM layer_poi_#{theme}(!bbox!, z(!scale_denominator!), !pixel_width!)) AS t"
query = query.gsub('{extra_attributes}', osm_tags_extra.map{ |t| "tags->'#{t}' AS \"#{t}\"" }.join(', '))
poi_yaml['layer']['datasource']['query'] = query

keep_fields = %w[geometry name name_en name_de superclass class subclass zoom priority style agg_stop layer level indoor rank]
poi_yaml['layer']['fields'] = poi_yaml['layer']['fields'].slice(*keep_fields).merge(osm_tags_extra.map{ |t| [t, ''] }.to_h)
File.write(layer_yaml, YAML.dump(poi_yaml))

file = File.open(mapping_yaml, 'w')
file.write("
tags:
  include: [#{include_tags}]
#{yaml_str.gsub('def_poi:', "def_#{theme}_poi: &poi_#{theme}_mapping").gsub('---', '')}

def_poi_#{theme}_fields: &poi_#{theme}_fields
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
  - name: access # for reject filters
    key: access
    type: string

tables:
  # etldoc: imposm3 -> osm_poi_#{theme}_point
  poi_#{theme}_point:
    type: point
    columns: *poi_#{theme}_fields
    mapping: *poi_#{theme}_mapping
    filters:
      reject:
        access: ['no']

  # etldoc: imposm3 -> osm_poi_#{theme}_polygon
  poi_#{theme}_polygon:
    type: polygon
    columns: *poi_#{theme}_fields
    mapping: *poi_#{theme}_mapping
    filters:
      reject:
        access: ['no']
")


whens = []
expressions = []
ontology['superclass'].collect{ |k_super, superclass|
  (superclass['class'] || {}).collect{ |k, classs|
    (classs['subclass'] || {}).collect{ |k_sub, subclass|
      [k_super, k, k_sub, subclass['zoom'], subclass['style'], subclass['priority'], subclass['osm_tags']]
    } + (classs['style'] ? [[k_super, k, nil, classs['zoom'], classs['style'], classs['priority'], classs['osm_tags']]] : [])
  }
}.flatten(2).sort.collect{ |superclass, classs, subclass, zoom, style, priority, osm_tags|
  superclass_sql = "'#{superclass}'"
  classs_sql = "'#{classs}'"
  subclass_sql = subclass ? "'#{subclass}'" : 'NULL'
  style_sql = style && style != '' ? "'#{style}'" : 'NULL'

  superclass_java = "\"#{superclass}\""
  classs_java = "\"#{classs}\""
  subclass_java = subclass ? "\"#{subclass}\"" : 'null'
  style_java = style && style != '' ? "'#{style}'" : 'null'

  zoom ||= 18

  tags_sql = []
  tags_java = []
  osm_tags[1..-2].split('][').collect{ |t|
    t.split(/(=|~=|=~|!=|!~|~)/, 2).collect(&:unquote)
  }.collect{ |k, o, v|
    if o.nil?
      tags_sql << "(tags?'#{k}' AND tags->'#{k}' != 'no')"
      tags_java << "and(matchField(\"#{k}\"), not(matchAny(\"#{k}\", \"no\")))"
    else
      if o == '='
        values_sql = "'#{v}'"
        values_java = "\"#{v}\""
        tags_sql << "tags?'#{k}' AND tags->'#{k}' = #{values_sql}"
        tags_java << "matchAny(\"#{k}\", #{values_java})"
      elsif o == '!~'
        # Treat regex as list
        values_sql = v.split('|').map{ |t| "'#{t}'" }
        values_java = v.split('|').map{ |t| "\"#{t}\"" }
        tags_sql << "(NOT tags?'#{k}' OR tags->'#{k}' NOT IN (#{values_sql.join(', ')}))"
        tags_java << "not(matchAny(\"#{k}\", #{values_java.join(', ')}))"
      else
        Raise 'Not implemented'
      end
    end
  }

  tags_java = tags_java.size == 1 ? tags_java[0] : "and(#{tags_java.join(', ')})"

  whens << if superclass_sql == "'remarkable'" && classs_sql == "'attraction_activity'" && subclass_sql == "'attraction'"
             "(SELECT
  #{superclass_sql}, #{classs_sql}, #{subclass_sql},
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
  WHERE #{tags_sql.join(' AND ')}
) AS score)"
           else
             "            SELECT #{superclass_sql}, #{classs_sql}, #{subclass_sql}, #{zoom}, #{style_sql}, #{priority} WHERE #{tags_sql.join(' AND ')}"
           end

  expressions << "MultiExpression.entry(
      new PoiClass(#{superclass_java}, #{classs_java}, #{subclass_java}, #{zoom}, #{style_java}, #{priority}),
      #{tags_java})"
}

file = File.open(class_sql, 'w')
file.write("
CREATE OR REPLACE FUNCTION poi_#{theme}_class(key TEXT, value TEXT, tags hstore) RETURNS TABLE (
    superclass TEXT,
    class TEXT,
    subclass TEXT,
    zoom INTEGER,
    style TEXT,
    priority INTEGER
) AS $$
    SELECT * FROM (
#{whens.join(" UNION ALL\n")}
    ) AS t(superclass, class, subclass, zoom, style, priority)
    ORDER BY
        zoom,
        priority
    LIMIT 1
$$
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE;
")

file = File.open(class_java, 'w')
file.write("package org.openmaptiles.layers;

import static com.onthegomap.planetiler.expression.Expression.*;

import com.onthegomap.planetiler.expression.MultiExpression;
import java.util.Arrays;

public class Poi#{theme.capitalize}Class {
  record PoiClass(
    String superclass,
    String class_,
    String subclass,
    int zoom,
    char style,
    int priority) {}

  static MultiExpression.Entry[] POI_CLASS_ENTRIES = {
    #{expressions.join(",\n    ")}
  };

  public static MultiExpression.Index<PoiClass> POI_CLASS =
    MultiExpression.of(Arrays.asList((MultiExpression.Entry<PoiClass>[]) POI_CLASS_ENTRIES)).simplify().index();
}
")


# // Multiple list as compier perf workaround
# //#{expressions.each_slice(25).collect{ |s| "MultiExpression.of(List.of(\n      " + s.join(",\n      ") + "\n    ))" }.join(",\n    ")}
