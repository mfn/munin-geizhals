#!/usr/bin/ruby

require 'rubygems'
require 'hpricot'
require 'net/http'

module Geizhals
    def self.parse_wishlist(html)
        doc = Hpricot html
        rows = doc.search '/html/body/div[3]/div[3]/table/tr'
        data = {}
        money = /(\d+),(\S+).*/
        rows.each { |row|

            cols = row.search '/td'

            if cols.length == 7
                name = cols[0].at 'span'
                next if !name
                next if name.inner_text.strip.length == 0

                price = cols[4].at 'span'
                next if !price
                next if !price.inner_text.strip.length == 0
                price = price.inner_text
                match = money.match price
                next if !match.length == 2

                data[ name.inner_text.strip ] = match[1].to_f + ( match[2].to_f / 100 )
            end
        }

        data
    end

    module Munin
        FIELD_FIRST = /^[^A-Za-z_]/
        FIELD_REST = /[^A-Za-z0-9_]/
        LABEL_EXCLUDE = /[#\\]/
        FIELD_TYPE = 'GAUGE'

        def self.config(html, graph_opts = {})
            fields = get_fields html
            if !graph_opts.key? 'graph_title'
                graph_opts['graph_title'] = 'Wishlist'
            end
            out = ''
            graph_opts.each { |k,v|
                out << "#{k} #{v}\n"
            }
            fields.each { |k,v|
                out << "#{k}.label #{v}\n"
                out << "#{k}.type #{FIELD_TYPE}\n"
            }
            out
        end
        def self.get_fields(html)
            fields = {}
            data = Geizhals.parse_wishlist html 
            return fields if data.length == 0
            data.each { |name,price|
                fields[normalize_field name] = normalize_label name
            }
            if data.length != fields.length
                throw "Duplicate field names after normalization, down from #{data.length} to #{fields.length}"
            end
            fields
        end
        def self.normalize_field(field)
            field.gsub(FIELD_FIRST, '_').gsub(FIELD_REST, '_').gsub(/_+/, '_').gsub(/_$/, '')
        end
        def self.normalize_label(label)
            label.gsub(LABEL_EXCLUDE, '_').gsub(/_$/, '')
        end
        def self.data(html)
            data = Geizhals.parse_wishlist html 
            out = ''
            data.each { |name,price|
                out << "#{normalize_field name}.value #{price}\n"
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
    elsif ARGV.length == 0
        puts Geizhals::Munin.data Geizhals::Munin.get_html_source
    else
        throw 'Unknown argument, use none or "config"'
    end
end
