#!/usr/bin/ruby

require 'rubygems'
require 'hpricot'
require 'net/http'

module Geizhals
    def self.parse_wishlist(html)
        doc = Hpricot html
        rows = doc.search '/html/body/div[3]/div[3]/table/tr'
        data = {}
        moneyRE = /(\d+),(\S+).*/
        countRE = /Anzahl: (\d+)/
        rows.each { |row|

            cols = row.search '/td'

            if cols.length == 7
                name = cols[0].at 'span'
                next if !name
                next if name.inner_text.strip.length == 0

                # We don't care if something goes wrong here
                begin
                    count = countRE.match(cols[0].at('a[2]').inner_text)[1].to_i
                rescue
                    count = 1
                end

                price = cols[4].at 'span'
                next if !price
                next if !price.inner_text.strip.length == 0
                price = price.inner_text
                match = moneyRE.match price
                next if !match.length == 2

                data[ name.inner_text.strip ] = {
                    :price => match[1].to_f + ( match[2].to_f / 100 ),
                    :count => count
                }
            end
        }

        data
    end

    module Munin
        FIELD_FIRST = /^[^A-Za-z_]/
        FIELD_REST = /[^A-Za-z0-9_]/
        FIELD_MAX_LEN = 20
        FIELD_TYPE = 'GAUGE'
        LABEL_EXCLUDE = /[#\\]/
        LABEL_MAX_LEN = 32

        def self.config(html, graph_opts = {})
            fields = get_fields html
            if !graph_opts.key? 'graph_title'
                graph_opts['graph_title'] = 'Wishlist'
            end
            out = ''
            graph_opts.each { |k,v|
                out << "#{k} #{v}\n"
            }
            fields.keys.sort.each { |k|
                out << "#{k}.label #{fields[k][0..LABEL_MAX_LEN]}\n"
                out << "#{k}.type #{FIELD_TYPE}\n"
            }
            out
        end
        def self.get_fields(html)
            fields = {}
            data = Geizhals.parse_wishlist html 
            return fields if data.length == 0
            data.each { |name,value|
                if value[:count] == 1
                    fields[normalize_field name] = normalize_label name
                else
                    fields[normalize_field name] = value[:count].to_s + 'x ' + normalize_label(name)
                end
            }
            if data.length != fields.length
                throw "Duplicate field names after normalization, down from #{data.length} to #{fields.length}"
            end
            fields
        end
        def self.normalize_field(field)
            field.gsub(FIELD_FIRST, '_').gsub(FIELD_REST, '_').gsub(/_+/, '_')[0..FIELD_MAX_LEN].gsub(/_$/, '')
        end
        def self.normalize_label(label)
            label.gsub(LABEL_EXCLUDE, ' ').gsub(/ +/, ' ').strip
        end
        def self.data(html)
            data = Geizhals.parse_wishlist html 
            out = ''
            data.keys.sort.each { |name|
                out << "#{normalize_field name}.value #{data[name][:price]}\n"
            }
            out
        end
        def self.get_html_source
            if ENV.key? 'file'
                return File.read ENV['file']
            elsif ENV.key? 'url'
                return Net::HTTP.get URI.parse ENV['url']
            end
            throw 'Cannot locate HTML source, use either environment variable "file" or "url"'
        end
    end
end

if $0 == __FILE__
    $stdout.sync = true

    if ARGV[0] == 'config'
        puts Geizhals::Munin.config Geizhals::Munin.get_html_source
    else
        puts Geizhals::Munin.data Geizhals::Munin.get_html_source
    end
end
