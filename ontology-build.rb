require 'csv'
require 'json'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

theme = ARGV[0]
name = ARGV[1]
superclass_csv = ARGV[2]
input_csv = ARGV[3]
tags_csv = ARGV[4]
ontology_json = ARGV[5]

superclasses = {}
current_superclasses = nil
CSV.new(File.new(superclass_csv).read, headers: true).collect{ |row|
  row.to_h.transform_values{ |v| v.nil? || v.strip == '' ? nil : v.strip }
}.collect{ |row|
  row.slice(*(['superclass', 'color_icon', 'color_text', 'class', 'superclass:name:fr'].map{ |k| "#{theme}_#{k}" } + %w[attributes_superclass attributes_class]))
}.each{ |row|
  if row["#{theme}_color_icon"]
    current_superclasses = row["#{theme}_superclass"]
    superclasses[current_superclasses] = {
      label: { en: current_superclasses, fr: row["#{theme}_superclass:name:fr"] },
      color_fill: row["#{theme}_color_icon"].downcase,
      color_line: row["#{theme}_color_text"].downcase,
      attributes: row['attributes_superclass'].split,
      class: {},
    }
  elsif row["#{theme}_class"]
    superclasses[current_superclasses][:class][row["#{theme}_class"]] = {
      attributes: row['attributes_class']&.split,
    }
  end
}


plus_groups = {}
current_group = {}
current_tag = {}
CSV.new(File.new(tags_csv).read, headers: true).collect{ |row|
  row.to_h.transform_values{ |v| v.nil? || v.strip == '' ? nil : v.strip }
}.collect{ |row|
  row.slice('tag', 'value', 'name:fr')
}.select{ |row|
  row['tag'] || row['value']
}.each{ |row|
  tag = row['tag']
  if tag&.start_with?('&')
    current_group = {}
    plus_groups[tag[1..]] = current_group
  elsif !tag.nil?
    current_tag = {
      label: { fr: row['name:fr'] },
      values: row['value'] == '*' ? nil : [],
    }
    current_group[tag] = current_tag
  else
    if current_tag[:values].nil?
      puts "Error: value for non enum key: #{row['value']}"
    end
    current_tag[:values] << { value: row['value'], label: { fr: row['name:fr'] } }
  end
}
plus_groups.each{ |group_id, group|
  group.each{ |tag, ct|
    if !ct[:values].nil? && ct[:values].empty?
      puts "Error: osm_tags_extra \"#{tag}\" with no values"
      ct[:values] = nil
    end
  }
}

csv = CSV.new(File.new(input_csv).read, headers: true).collect{ |row|
  row.to_h.transform_values{ |v| v.nil? || v.strip == '' ? nil : v.strip }
}.collect{ |row|
  row.slice(*(['superclass:name:fr', 'superclass', 'class:name:fr', 'class', 'zoom', 'style', 'priority'].map{ |k| "#{theme}_#{k}" } + ['name_over_value', 'key', 'value', 'name:fr', 'attributes', 'overpass']))
}.select{ |row|
  row["#{theme}_superclass"]
}.map{ |row|
  row['attributes'] = (
    (superclasses.dig(row["#{theme}_superclass"], :attributes) || []) +
    (superclasses.dig(row["#{theme}_superclass"], :class, row["#{theme}_class"], :attributes) || []) +
    (row['attributes']&.split || [])
  ).collect{ |a| a[1..-1] }
  row
}


error = csv.select{ |row|
  row.slice("#{theme}_priority", "#{theme}_superclass", 'key', 'value').any?{ |k, v|
    k.nil? || v.nil? || k.include?(' ') || v.include?(' ')
  } or ![nil, '', '⬤', '◯', '•'].include?(row["#{theme}_style"])
}

if !error.empty?
  puts 'ERROR: invalid row'
  error.each{ |row| puts row.inspect }
  exit 1
end


names = csv.collect{ |row|
  row['name_over_value'] || row['value']
}.group_by{ |r| r }.transform_values(&:size).select{ |_k, s| s >= 2 }

if !names.empty?
  puts 'ERROR: duplicate row names'
  puts names.inspect
  exit 1
end


hierarchy = csv.group_by{ |row| row["#{theme}_superclass"] }.collect{ |superclass, c|
  c0 = c[0]
  c = c.collect{ |r|
    r.slice(*(['class:name:fr', 'class', 'zoom', 'style', 'priority'].map{ |k| "#{theme}_#{k}" } + ['name_over_value', 'value', 'name:fr', 'attributes', 'overpass']))
  }.group_by{ |r| r["#{theme}_class"] }.collect{ |classs, sc|
    sc0 = sc[0]
    sc = sc.collect{ |rr|
      value = rr['name_over_value'] || rr['value']
      [value, {
        label: { en: value, fr: rr['name:fr'] },
        zoom: rr["#{theme}_zoom"].to_i,
        style: rr["#{theme}_style"],
        priority: rr["#{theme}_priority"].to_i,
        osm_tags: rr['overpass'].split(';'),
        osm_tags_extra: rr['attributes'],
      }]
    }.to_h
    if sc
      [classs, {
        label: { en: classs, fr: sc0["#{theme}_class:name:fr"] },
        subclass: sc,
      }]
    else
      [classs, {
        label: { en: classs, fr: sc0["#{theme}_class:name:fr"] },
        zoom: sc0["#{theme}_zoom"].to_i,
        style: sc0["#{theme}_style"],
        priority: sc0["#{theme}_priority"].to_i,
      }]
    end
  }.to_h
  pop = c.delete(nil)
  pop = pop[:subclass] if pop
  [superclass, {
    label: superclasses[superclass][:label],
    color_fill: superclasses[superclass][:color_fill],
    color_line: superclasses[superclass][:color_line],
    class: c.merge(pop || {}),
  }]
}.to_h
file = File.open(ontology_json, 'w')
file.write(JSON.pretty_generate({
  name: name,
  superclass: hierarchy,
  osm_tags_extra: plus_groups,
}))
