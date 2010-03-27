#!/usr/bin/ruby

=begin rdoc

=Synopsis
A munin plug-in for graphing geizhals.at wishlists.

=Requirements
Requires the +hpricot+ ruby library. Usually installable via gems, e.g. <tt>gem
install hpricot</tt>.

=Usage
This ruby code is self-running, which means the file <tt>munin_geizhals.rb</tt>
can be either used in a library context or directly invoked from the shell. 

==Munin installation guide
* Create a symlink in your <tt>/etc/munin/plugins/</tt> directory, e.g. <tt>ln -s geizhals_pc1 /path/to/munin_geizhals.rb</tt>
* Configure the plugin

  Munin plug-ins are configured in <tt>/etc/munin/plugin-conf.d/</tt>, you can
  e.g. create a file <tt>geizhals</tt> there. The a sample section looks like
   [geizhals_pc1]
   env.type area
   env.file /path/to/your/geizhals/wishlist.html

  * Which type of graph do you want

    Set the environment variable +type+ to either +lines+, +lines_with_total+ or
    +area+. Defaults to +lines+.

  * Where to parse the wishlist data (HTML) from

    Two sources are possible: a local file or an URL to fetch. Using the URL
    directly from the munin plug-in is *discouraged* because this would createa
    request to geizhals every time the plug-in runs (defaults to five minutes).
    This is often actually quite unnecessary, price do not change that fast.

    The *recommended* approach is to configure the plug-in to parse the HTML
    from a local file and use other means to fetch the HTML from geizhals, e.g.
    using wget every once in a while.

    For this to work, use the environment variable +file+ as shown above. The
    other possibility would be to use the environment variable +url+ instead.

At this point, everything is done and munin needs to be restarted.

If you want to use wget to fetch your wishlist URL, you can use this cron job line
(note: your wishlist URL needs to be public!):

<tt>0 0 * * * tmp=`mktemp` ; wget -q 'your wishlist url' -O $tmp ; if [ "$?" = "0" ]; then mv $tmp /path/to/your/geizhals/wishlist.html; fi ; rm $tmp 2> /dev/null</tt>

This include some basic error checking, in case the URL could not be fetched.

==Library usage
Using Geizhals#parse_wishlist you can get a hash of your wishlist items. Every
item has a name, a (per unit) price and how many units. The method uses the
hpricot library and xpath selectors to finds its way through the HTML soup.

The other public methods, Geizhals::Munin#config and Geizhals::Munin#data return
a string which can be directly sent to stdout when acting as a munin plug-in.

=end

require 'rubygems'
require 'hpricot'
require 'net/http'

module Geizhals
    public
=begin rdoc
    Parses a geizhals wishlist HTML and returns a hash with the wishlist items.

    The method uses the hpricot library and xpath queries to find the items.

    Return value:
     {'item1' => { :price => 100.00, :count => 1 }, 'item2' => ...}
=end
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
=begin rdoc
    Munin plugin related methods.

    For munin itself, see http://munin-monitoring.org .
=end
    module Munin
        public
        FIELD_FIRST = /^[^A-Za-z_]/
        FIELD_REST = /[^A-Za-z0-9_]/
        FIELD_MAX_LEN = 20
        LABEL_EXCLUDE = /[#\\]/
        LABEL_MAX_LEN = 32
=begin rdoc
        Returns the munin plug-in configuration string.

        html - wishlist HTML

        type - tell munin how to render the graph. Valid values: +lines+
        (default), +lines_with_total+ and +area+. Must match the +type+
        parameter when calling Geizhals::Munin#data .

        graph_opts - Optional hash to pass additional information to munin
=end
        def self.config(html, type = 'lines', graph_opts = {})
            fields = get_fields html
            if !graph_opts.key? 'graph_title'
                graph_opts['graph_title'] = 'Wishlist'
            end
            out = ''
            graph_opts.each { |k,v|
                out << "#{k} #{v}\n"
            }
            first = true
            fields.keys.sort.each { |k|
                out << "#{k}.label #{fields[k][0..LABEL_MAX_LEN]}\n"
                out << "#{k}.type GAUGE\n"
                if type == 'area'
                    if first
                        out << "#{k}.draw AREA\n"
                        first = false
                    else
                        out << "#{k}.draw STACK\n"
                    end
                end
            }
            if type == 'lines_with_total'
                out << "sum.label Sum\n"
                out << "sum.type GAUGE\n"
            end
            out
        end
=begin rdoc
        Returns the munin plug-in data string.

        html - wishlist HTML

        type - tell munin how to render the graph. Valid values: +lines+
        (default), +lines_with_total+ and +area+. Must match the +type+
        parameter when calling Geizhals::Munin#config . Actually, this parameter
        does not affect the rendering itself but ensures that all the data
        requires for the graph type are present.
=end
        def self.data(html, type = 'lines')
            data = Geizhals.parse_wishlist html 
            out = ''
            sum_price = 0
            data.keys.sort.each { |name|
                price = data[name][:price] * data[name][:count]
                out << "#{normalize_field name}.value #{price}\n"
                sum_price += price
            }
            if type == 'lines_with_total'
                out << "sum.value #{sum_price}\n"
            end
            out
        end
        private
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

    type = ENV['type']

    if ARGV[0] == 'autoconf'
        puts "no\n"
        exit 1
    elsif ARGV[0] == 'config'
        puts Geizhals::Munin.config(Geizhals::Munin.get_html_source, type)
    else
        puts Geizhals::Munin.data(Geizhals::Munin.get_html_source, type)
    end

    exit 0
end
