require 'csv'
require 'json'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

theme = ARGV[0]
name = ARGV[1]
input_csv = ARGV[2]
tags_csv = ARGV[3]
ontology_json = ARGV[4]

plus_tags = CSV.new(File.new(tags_csv).read, headers: true).collect{ |row|
  row['tag'].gsub(' ', '').gsub(' ', '')
}.select{ |tag|
  tag != ''
}.uniq


csv = CSV.new(File.new(input_csv).read, headers: true).collect{ |row|
  row.to_h.transform_values{ |v| v.strip == '' ? nil : v.strip }
}.collect{ |row|
  row.slice(*(['superclass:name:fr', 'superclass', 'class:name:fr', 'class', 'zoom', 'style', 'priority'].map{ |k| "#{theme}_#{k}" } + ['key', 'value', 'extra_tags', 'name:fr']))
}.select{ |row|
  row["#{theme}_superclass"]
}.map{ |row|
  begin
    if row['extra_tags']
      row['extra_tags'] = row['extra_tags'].split(',').map{ |kv|
        kv.split('=').map(&:strip)
      }.to_h
    end
    row
  rescue StandardError
    puts 'ERROR extra_tags'
    puts row['extra_tags'].inspect
    exit 1
  end
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



hierarchy = csv.group_by{ |row| row["#{theme}_superclass"] }.collect{ |superclass, c|
  c0 = c[0]
  c = c.collect{ |r|
    r.slice(*(['class:name:fr', 'class', 'zoom', 'style', 'priority'].map{ |k| "#{theme}_#{k}" } + ['key', 'value', 'extra_tags', 'name:fr']))
  }.group_by{ |r| r["#{theme}_class"] }.collect{ |classs, sc|
    sc0 = sc[0]
    sc = sc.collect{ |rr|
      [rr['value'], {
        label: { en: rr['value'], fr: rr['name:fr'] },
        zoom: rr["#{theme}_zoom"].to_i,
        style: rr["#{theme}_style"],
        priority: rr["#{theme}_priority"].to_i,
        osm_tags: [{ rr['key'] => rr['value'] }.merge(rr['extra_tags'] || {})]
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
    label: { en: superclass, fr: c0["#{theme}_superclass:name:fr"] },
    class: c.merge(pop || {}),
  }]
}.to_h
file = File.open(ontology_json, 'w')
file.write(JSON.pretty_generate({
  name: name,
  superclass: hierarchy,
  osm_tags_extra: plus_tags,
}))
