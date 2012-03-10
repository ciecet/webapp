require 'util'
require 'webapp'
require 'webrick/httputils'
require "rexml/document"
require 'rexml/xpath'
require 'fileutils'
require 'stringio'

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

        op = ctx.queries["o"]
        ap = ctx.vars['APP_PATH'] - ['.cache']
        bp = ctx.vars['BASE_PATH']
        hostpath = ([@source]+ap).join("/")

        unless op
            sp = @pathmap[ap]
            if sp
                case sp[0]
                when :podcast
                    op = "browsepodcast"
                when :remote
                    op = "remote"
                end
            else
                if File.file?(hostpath)
                    op = "static"
                elsif File.directory?(hostpath)
                    op = "browse"
                end
            end
        end
        raise "Invalid path" unless op

        case op
        when "static"
            WebApp::File.new(hostpath).call ctx
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
                each_mp3(hostpath) { |mp3f|
                    pipe[1].puts mp3f
                }
            ensure
                pipe[1].close
                Process.detach(pid)
            end
        when "browse"
            out = StringIO.new
            out << "<html><head><meta http-equiv='content-type' content='text/html; charset=UTF-8' /><meta name='viewport' content='width=device-width, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no'/><title>"
            out << ap.join(" / ").to_html
            out << %(</title></head><body style="font-size:200%;">)
            out2 = []
            out2 << %(<a href="/#{bp.join("/").to_http}">HOME</a>)
            ap.each_index { |i|
                out2 << %(<a href="/#{(bp+ap[0..i]).join("/").to_http}">#{ap[i].to_html}</a>)
            }
            out << %(<h2>#{out2.join(" / ")}</h2>)

            @pathmap.each {|k,v|
                next unless k[0...-1] == ap
                out << %(<b>[#{v[0].to_s.upcase}]<b> <a href="/#{(bp+k).join("/").to_http}">#{k.last.to_html}</a><br>)
            }

            entries = Dir.new(hostpath).sort - [".", ".."]
            dirs = entries.find_all {|e| File.directory?(hostpath+"/"+e)}
            images = entries.find_all {|e| e =~ /\.(jpg|png|gif|bmp)$/i }
            mp3s = entries.find_all {|e| e=~ /\.mp3$/i }
            etc = entries - dirs - images - mp3s

            dirs.each { |e|
                next if e =~ /^\./
                out << %(<b>[FOLDER]</b> <a href="/#{(bp+ap+[e]).join("/").to_http}">#{e.to_html}</a><br>)
            }

            cid = 0
            out << %(<script type="text/javascript">)
            out << %(imagePaths = [ #{images.map{|e|(bp+ap+[e]).join("/").to_http.inspect}.join(", ")} ];)
            out << %(imageNames = [ #{images.map{|e|"'"+e.to_html.gsub("'","\\'")+"'"}.join(", ")} ];)
            out << %q{
            function showImage(id) {
                d = document.getElementById("imageframe");
                if (id < 0 || id >= imagePaths.length) {
                    d.innerHTML = "";
                    d.style.display = "none";
                    return;
                }
                
                ihtml = "";
                ihtml +="<div style='position:absolute;left:2%;top:2%;width:96%;height:96%;background:url(/"+imagePaths[id]+"?o=thumbnail);background-size:contain;background-repeat:no-repeat;background-position:center center;background-origin:content-box;'></div>";
                ihtml += "<div style='position:absolute;left:2%;top:2%;width:96%;height:96%;text-align:center;background:url(/"+imagePaths[id]+");background-size:contain;background-repeat:no-repeat;background-position:center center;background-origin:content-box;'>";
                ihtml += "<center><a style='color:white;background-color:rgba(0,0,0,0.5);' href='/"+imagePaths[id]+"'>"+imageNames[id]+"</a></center></div>";
                ihtml += "<div style='width:60%;height:90%;position:absolute;top:10%;left:20%;' onclick='showImage(-1);'></div>";
                ihtml += "<div style='width:20%;height:100%;position:absolute;left:0%;' onclick='showImage("+(id-1)+");'></div>";
                ihtml += "<div style='width:20%;height:100%;position:absolute;right:0%;' onclick='showImage("+(id+1)+");'></div>";
                d.innerHTML = ihtml;
                d.style.display = "inherit";
            }}.htrim
            out << %(</script>)
            out << %(<div style="z-index:9999;display:none;background-color:rgba(0,0,0,0.5);position:fixed;top:0%;bottom:0%;left:0%;right:0%;overflow:hidden;" id="imageframe"></div>)
            images.each { |e|
                p = (bp+ap+[e]).join("/").to_http
                abr = e[0...-4]
                if abr.length > 12
                    abr[12..-1] = ""
                end
                #out << %(<div style="position:relative;float:left;height:130px;overflow:hidden;" title="#{e.to_html}"><a href="?p=#{p}">)
                out << %(<div style="position:relative;float:left;height:130px;overflow:hidden;" title="#{e.to_html}"><a onclick="showImage(#{cid});">)
#                if File.file?("#{BASE_DIR}/cache/thumb/#{p}.jpg")
#                    out << %(<image style="padding:1px;" src="#{env["BASE_URL"]}/#{WEBrick::HTTPUtils.escape("thumb/#{p}.jpg")}"></image>)
#                else
                    out << %(<image style="padding:1px;" src="/#{p}?o=thumbnail"></image>)
#                end
                out << %(</a>)
                out << %(<div style="color:black;font-size:12px;position:absolute;top:3px;left:3px;">#{abr.to_html}</div>)
                out << %(<a href="/#{p}" style="text-decoration:none"><div style="color:white;font-size:12px;position:absolute;top:2px;left:2px;">#{abr.to_html}</div></a>)
                out << %(</div>)
                cid += 1
            }
            out << %(<div style="clear:both;"></div>)

            if mp3s.size > 1
                p = (bp+ap).join("/").to_http
                out << %(<h3><a href="/#{p}?o=playlist">PlayAll</a>)
                out << %( (<a href="/#{p}?o=playlistlow">Low</a>)</h3>)
            end

            mp3s.each { |e|
                p = (bp+ap+[e]).join("/").to_http
                out << %(<a href="/#{p}">#{e.to_html}</a>)
                out << %( -- (<a href="/#{p}?o=playlistlow">low</a>))
                out << %(<br>)
            }

            out << %(<table style="font-size:100%;">)
            etc.each { |e|
                p = (bp+ap+[e]).join("/").to_http
                size = File.size(hostpath+"/"+e)
                sizeh = size.to_s
                ["K", "M", "G"].each { |u|
                    break if size < 1000
                    sizeh = sprintf("%.1f%s", size.to_f/1024, u)
                    size /= 1024
                }
                out << "<tr>"
                out << %(<td align="right" style="padding-right:10px;">#{sizeh}</td><td><a href="/#{p}">#{e.to_html}</a></td>)
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
            throw "Invalid thumbnail path" unless File.file?(hostpath)
            thumbdir = File.dirname(hostpath)+"/.cache"
            thumbfile = thumbdir+"/thumb:"+ap.last

            unless File.file?(thumbfile)
                FileUtils.mkdir_p(thumbdir)
                open(thumbdir+"/lock:", "w") { |f|
                    f.flock(File::LOCK_EX)
                    system("convert", "-resize", "128x128", hostpath, thumbfile)
                }
            end

            WebApp::File.new(thumbfile, "image/jpeg").call ctx
        when "browsepodcast"
            out = StringIO.new
            out << "<html><head><meta http-equiv='content-type' content='text/html; charset=UTF-8' /><title>"
            out << ap.join(" / ").to_html
            out << %(</title></head><body style="font-size:200%;">)

            out2 = []
            out2 << %(<a href="/#{bp.join("/").to_http}">HOME</a>)
            ap.each_index { |i|
                out2 << %(<a href="/#{(bp+ap[0..i]).join("/").to_http}">#{ap[i].to_html}</a>)
            }
            out << %(<h2>#{out2.join(" / ")}</h2>)
            xml = REXML::Document.new(`curl -s '#{@pathmap[ap][1]}'`.force_encoding("ASCII-8BIT"))
            REXML::XPath.each(xml.root, "//item") { |e|
                l = []
                REXML::XPath.each(e, 'title/text()|enclosure/@url') { |i|
                    l << i.value
                }
                next unless l.size == 2
                #p = [safe_encode(ap[0]), safe_encode(l[1])].join("/")
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
            ctx.reply 302, %(Location: #{ap[1]})
        when "remote"
            # guess content-type and stream
            ctx.reply 302, %(Location: #{@pathmap[ap][1]})
        else
            raise "Unknown operation:#{op}"
        end
    end
end
