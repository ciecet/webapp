require 'util'
require 'webapp'
require 'webrick/httputils'
require "rexml/document"
require 'rexml/xpath'
require 'fileutils'
require 'stringio'

BASE_DIR = File.dirname(File.realpath(__FILE__))

class MediaBrowser

    def initialize src=".", pathmap={}
        @source = src
        @pathmap = pathmap
    end

    def each_mp3 path, &proc
        if File.file?(path)
            if path =~ /\.mp3$/i
                yield path
            end
        end

        if File.directory?(path)
            (Dir.new(path).sort - [".", ".."]).each { |ent|
                each_mp3 path+"/"+ent, &proc
            }
        end
    end

    def call ctx
        io = ctx.io
        env = ctx.env

        op = env["o"]
        path = env["p"] || ""
        path = path.split("/").map{|p|safe_decode(p)} - ["", ".", ".."]
        fullpath = ([@source]+path).join("/")

        unless op
            sp = @pathmap[path]
            if sp
                case sp[0]
                when :podcast
                    op = "browsepodcast"
                when :remote
                    op = "remote"
                end
            else
                if File.file?(fullpath)
                    op = "static"
                elsif File.directory?(fullpath)
                    op = "browse"
                end
            end
        end
        raise "Invalid path" unless op

        case op
        when "static"
            WebApp::File.new(fullpath).call ctx
        when "playlist", "playlistlow"
            ctx.reply 200,
                "Cache-Control: no-cache",
                "Pragma: no-cache",
                "Connection: close",
                "Content-Type: audio/mpeg"

            lowopt = ("-q 0 -V 0" if op == "playlistlow")

            begin
                pipe = IO.pipe
                pid = Process.spawn("mpg123 -s --list - | lame -r --vbr-new #{
                        lowopt} - -", :in => pipe[0], :out => io)
                each_mp3(fullpath) { |mp3f|
                    pipe[1].puts mp3f
                }
            ensure
                pipe[1].close
                Process.detach(pid)
            end
        when "browse"
            out = StringIO.new
            out << "<html><head><meta http-equiv='content-type' content='text/html; charset=UTF-8' /><title>"
            out << path.join(" / ").to_html
            out << %(</title></head><body style="font-size:200%;">)
            out2 = []
            out2 << %(<a href="?p=">HOME</a>)
            ap = []
            path.each { |p|
                ap << p
                out2 << %(<a href="?p=#{ap.map{|p|safe_encode(p)}.join("/")}">#{p.to_html}</a>)
            }
            out << %(<h2>#{out2.join(" / ")}</h2>)

            @pathmap.each {|k,v|
                next unless k[0...-1] == path
                out << %(<b>[#{v[0].to_s.upcase}]<b> <a href="?p=#{safe_encode(k.last)}">#{k.last.to_html}</a><br>)
            }

            entries = Dir.new(fullpath).sort - [".", ".."]
            dirs = entries.find_all {|e| File.directory?(fullpath+"/"+e)}
            images = entries.find_all {|e| e =~ /\.(jpg|png|gif|bmp)$/i }
            mp3s = entries.find_all {|e| e=~ /\.mp3$/i }
            etc = entries - dirs - images - mp3s

            dirs.each { |e|
                next if e =~ /^\./
                p = (path+[e]).map{|p|safe_encode(p)}.join("/")
                out << %(<b>[FOLDER]</b> <a href="?p=#{p}">#{e.to_html}</a><br>)
            }

            cid = 0
            out << %(<script type="text/javascript">)
            out << %(imagePaths = [ #{images.map{|e|(path+[e]).map{|p|safe_encode(p)}.join("/").inspect}.join(", ")} ];)
            out << %(imageNames = [ #{images.map{|e|"'"+e.to_html.gsub("'","\\'")+"'"}.join(", ")} ];)
            out << %q{
            function showImage(id) {
                d = document.getElementById("imageframe");
                if (id < 0 || id >= imagePaths.length) {
                    d.innerHTML = "";
                    d.style.display = "none";
                    return;
                }
                ihtml = "<div style='width:100%;height:100%;text-align:center;background:url(?p="+imagePaths[id]+");background-size:contain;background-repeat:no-repeat;background-position:center center;background-origin:content-box;'>";
                ihtml += "<a style='color:white;background-color:rgba(0,0,0,0.5);display=inline;' href='?p="+imagePaths[id]+"'>"+imageNames[id]+"</a>";
                ihtml += "<div style='width:60%;height:90%;position:absolute;top:10%;left:20%;' onclick='showImage(-1);'></div>";
                ihtml += "<div style='width:20%;height:100%;position:absolute;left:0%;' onclick='showImage("+(id-1)+");'></div>";
                ihtml += "<div style='width:20%;height:100%;position:absolute;right:0%;' onclick='showImage("+(id+1)+");'></div>";
                ihtml += "</div>";
                d.innerHTML = ihtml;
                d.style.display = "inherit";
            }}.htrim
            out << %(</script>)
            out << %(<div style="z-index:9999;display:none;background-color:rgba(0,0,0,0.5);position:fixed;top:0%;bottom:0%;left:0%;right:0%;overflow:hidden;" id="imageframe"></div>)
            images.each { |e|
                p = (path+[e]).map{|p|safe_encode(p)}.join("/")
                abr = e[0...-4]
                if abr.length > 12
                    abr[12..-1] = ""
                end
                #out << %(<div style="position:relative;float:left;height:130px;overflow:hidden;" title="#{e.to_html}"><a href="?p=#{p}">)
                out << %(<div style="position:relative;float:left;height:130px;overflow:hidden;" title="#{e.to_html}"><a onclick="showImage(#{cid});">)
#                if File.file?("#{BASE_DIR}/cache/thumb/#{p}.jpg")
#                    out << %(<image style="padding:1px;" src="#{env["BASE_URL"]}/#{WEBrick::HTTPUtils.escape("thumb/#{p}.jpg")}"></image>)
#                else
                    out << %(<image style="padding:1px;" src="?o=thumbnail&p=#{p}"></image>)
#                end
                out << %(</a>)
                out << %(<div style="color:black;font-size:12px;position:absolute;top:3px;left:3px;">#{abr.to_html}</div>)
                out << %(<div style="color:white;font-size:12px;position:absolute;top:2px;left:2px">#{abr.to_html}</div>)
                out << %(</div>)
                cid += 1
            }
            out << %(<div style="clear:both;"></div>)

            if mp3s.size > 1
                p = path.map{|p|safe_encode(p)}.join("/")
                out << %(<h3><a href="?o=playlist&p=#{p}">PlayAll</a>)
                out << %( (<a href="?o=playlistlow&p=#{p}">Low</a>)</h3>)
            end

            mp3s.each { |e|
                p = (path+[e]).map{|p|safe_encode(p)}.join("/")
                out << %(<a href="?p=#{p}">#{e.to_html}</a>)
                out << %( -- (<a href="?o=playlistlow&p=#{p}">low</a>))
                out << %(<br>)
            }

            out << %(<table style="font-size:100%;">)
            etc.each { |e|
                p = (path+[e]).map{|p|safe_encode(p)}.join("/")
                size = File.size(fullpath+"/"+e)
                sizeh = size.to_s
                ["K", "M", "G"].each { |u|
                    break if size < 1000
                    sizeh = sprintf("%.1f%s", size.to_f/1024, u)
                    size /= 1024
                }
                out << "<tr>"
                out << %(<td align="right" style="padding-right:10px;">#{sizeh}</td><td><a href="?p=#{p}">#{e.to_html}</a></td>)
                out << "</tr>"
            }
            out << %(</table>)

            out << "</body></html>"

            ctx.reply 200,
                "Cache-Control: no-cache",
                "Pragma: no-cache",
                "Connection: close",
                "Content-Type: text/html"
            io.puts out.string
        when "thumbnail"
            thumbfile = %(#{BASE_DIR}/cache/thumb/#{path.map{|p|safe_encode(p)}.join("/")}.jpg)
            unless File.file?(thumbfile)
                FileUtils.mkdir_p(File.dirname(thumbfile))
                open("#{BASE_DIR}/cache/.lock", "w") { |f|
                    f.flock(File::LOCK_EX)
                    system("convert", "-resize", "128x128", fullpath, thumbfile)
                }
            end

            WebApp::File.new(thumbfile, "image/jpeg").call ctx
        when "browsepodcast"
            out = StringIO.new
            out << "<html><head><meta http-equiv='content-type' content='text/html; charset=UTF-8' /><title>"
            out << path.join(" / ").to_html
            out << %(</title></head><body style="font-size:200%;">)

            out2 = []
            out2 << %(<a href="?p=">HOME</a>)
            ap = []
            path.each { |p|
                ap << p
                out2 << %(<a href="?p=#{ap.map{|p|safe_encode(p)}.join("/")}">#{p.to_html}</a>)
            }
            out << %(<h2>#{out2.join(" / ")}</h2>)
            xml = REXML::Document.new(`curl -s '#{@pathmap[path][1]}'`.force_encoding("ASCII-8BIT"))
            REXML::XPath.each(xml.root, "//item") { |e|
                l = []
                REXML::XPath.each(e, 'title/text()|enclosure/@url') { |i|
                    l << i.value
                }
                next unless l.size == 2
                p = [safe_encode(path[0]), safe_encode(l[1])].join("/")
                #out << %(<b>[EPISODE]</b> <a href="?o=playpodcast&p=#{p}">#{l[0].to_html}</a>)
                out << %(<b>[EPISODE]</b> <a href="#{l[1]}">#{l[0].to_html}</a><br>)
            }
            out << "</body></html>"

            ctx.reply 200,
                "Cache-Control: no-cache",
                "Pragma: no-cache",
                "Connection: close",
                "Content-Type: text/html"
            ctx.io.puts out.string
        when "playpodcast"
            # guess content-type and stream
            ctx.reply 302, %(Location: #{path[1]})
        when "remote"
            # guess content-type and stream
            ctx.reply 302, %(Location: #{@pathmap[path][1]})
        else
            raise "Unknown operation:#{op}"
        end
    end
end
