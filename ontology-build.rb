require 'csv'
require 'json'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

input_csv = ARGV[0]
tags_csv = ARGV[1]
ontology_json = ARGV[2]

plus_tags = CSV.new(File.new(tags_csv).read, headers: true).collect{ |row|
  row['tag'].gsub(' ', '').gsub(' ', '')
}.select{ |tag|
  tag != ''
}.uniq


superclass_name_fr = class_name_fr = subclass_name_fr = nil
csv = CSV.new(File.new(input_csv).read, headers: true).collect{ |row|
  row.to_h.transform_values{ |v| v == '' ? nil : v }
}.collect{ |row|
  row.to_h.slice('superclass:name:fr', 'superclass', 'class:name:fr', 'class', 'subclass:name:fr', 'zoom', 'style', 'priority', 'key', 'value', 'extra_tags')
}.collect{ |row|
  if row['superclass:name:fr']
    superclass_name_fr = row['superclass:name:fr']
    class_name_fr = subclass_name_fr = nil
  end
  if row['class:name:fr']
    class_name_fr = row['class:name:fr']
    subclass_name_fr = class_name_fr
  end

  subclass_name_fr = row['subclass:name:fr'] if row['subclass:name:fr']
  row['superclass:name:fr'] = superclass_name_fr
  row['class:name:fr'] = class_name_fr
  row['subclass:name:fr'] = subclass_name_fr
  row
}.select{ |row|
  row['superclass']
}.map{ |row|
  row['extra_tags'] = Hash[row['extra_tags'].split(',').map{ |kv|
    kv.split('=').map(&:strip)
  }] if row['extra_tags']
  row
}


error = csv.select{ |row|
  row.slice('priority', 'superclass', 'key', 'value').any?{ |k, v|
    k.nil? || v.nil? || k.include?(' ') || v.include?(' ')
  } or ![nil, '', '⬤', '◯', '•'].include?(row['style'])
}

if !error.empty?
  puts 'ERROR'
  error.each{ |row| puts row.inspect }
  exit 1
end


hierarchy = Hash[csv.group_by{ |row| row['superclass'] }.collect{ |superclass, c|
  c0 = c[0]
  c = Hash[c.collect{ |r|
    r.slice('class:name:fr', 'class', 'subclass:name:fr', 'zoom', 'style', 'priority', 'key', 'value', 'extra_tags')
  }.group_by{ |r| r['class'] }.collect{ |classs, sc|
    sc0 = sc[0]
    sc = Hash[sc.collect{ |rr|
      [rr['value'], {
        label: { en: rr['value'], fr: rr['subclass:name:fr'] },
        zoom: rr['zoom'].to_i,
        style: rr['style'],
        priority: rr['priority'].to_i,
        osm_tags: [{ rr['key'] => rr['value'] }.merge(rr['extra_tags'] || {})]
      }]
    }]
    if sc
      [classs, {
        label: { en: classs, fr: sc0['class:name:fr'] },
        subclass: sc,
      }]
    else
      [classs, {
        label: { en: classs, fr: sc0['class:name:fr'] },
        zoom: sc0['zoom'].to_i,
        style: sc0['style'],
        priority: sc0['priority'].to_i,
      }]
    end
  }]
  pop = c.delete(nil)
  pop = pop[:subclass] if pop
  [superclass, {
    label: { en: superclass, fr: c0['superclass:name:fr'] },
    class: c.merge(pop || {}),
  }]
}]
file = File.open(ontology_json, 'w')
file.write(JSON.pretty_generate({
  name: 'Ontology Tourism',
  superclass: hierarchy,
  osm_tags_extra: plus_tags,
}))
