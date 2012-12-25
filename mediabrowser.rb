require 'util'
require "rexml/document"
require 'rexml/xpath'
require 'fileutils'
require 'stringio'
require 'webapp'
require 'textpager'

class MediaBrowser

    def initialize src=".", admins=nil
        @source = src
        @admins = admins
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

    def canread? path, user
        checkread(path, user) || checkread(path, "anyone")
    end

    def checkread path, user
        File.file?(File.dirname(path)+
                "/.cache/access/#{user}/#{File.basename(path)}")
    end

    def checkbox hostpath, urlpath, user
        r = checkread(hostpath, user)
        %(<input style="width:20px;height:20px;" type="checkbox" #{
            "checked='checked'" if r
        } onclick="request('/#{urlpath}?a=1&o=ac&m=#{
            "r" unless r
        }&u=#{user}','')"></input> )
    end

    def audioPlayer
        %{
            <script type="text/javascript">
                function playAudio(url) {
                    p = document.getElementById("audioframe");
                    ihtml = '<audio id="audioplayer" style="width:100%;" controls="controls" preload="auto" autoplay="autoplay" src="'+url+'"></audio>';
                    p.innerHTML = ihtml;
                    p.style.visibility = "visible";

                    p = document.getElementById("audioplayer");
                    p.play();
                    return false;
                }
            </script>
            <div style="z-index:9998;visibility:hidden;background-color:rgba(255,255,255,0.7);position:fixed;bottom:2%;left:2%;right:2%;overflow:hidden;" id="audioframe"></div>
        }.htrim 
    end

    def call ctx
        op = ctx.queries["o"]
        ap = ctx.vars['APP_PATH'] - ['.cache']
        bp = ctx.vars['BASE_PATH']
        hostpath = ([@source]+ap).join("/")
        privileged = false
        invitee = nil

        user = ctx.vars['SESSION_USER']
        if !@admins || @admins.include?(user)
            privileged = true
            invitee = ctx.cookies["invitee"]
            invitee = ctx.queries["invitee"] if ctx.queries.include?("invitee")
            if invitee && !(invitee == 'anyone' ||
                    invitee =~ /^[a-zA-Z0-9.]+@[a-zA-Z0-9.]+$/)
                invitee = nil
            end
        else
            unless ap.empty? || canread?(hostpath, user)
                throw "Access denied for user:#{user}"
            end
        end

        unless op
            if File.file?(hostpath)
                op = case hostpath
                when /\.pod$/; "browsepodcast"
                when /\.url$/; "remote"
                when /\.txt$/; "textpager"
                else; "static" end
            elsif File.directory?(hostpath)
                op = "browse"
            end
        end
        raise "Invalid path" unless op

        case op
        when "static"
            WebApp::File.new(hostpath).call ctx
        when "textpager"
            TextPager.new(hostpath).call ctx
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
                        lowopt} - -", :in => pipe[0], :out => ctx.io)
                each_mp3(hostpath) { |mp3f|
                    pipe[1].puts mp3f
                }
            ensure
                pipe[1].close
                Process.detach(pid)
            end
        when "ac"
            throw "Unauthorized" unless invitee
            dir = File.dirname(hostpath)+"/.cache/access/#{invitee}"
            file = dir+"/#{File.basename(hostpath)}"
            case ctx.queries['m']
            when "r"
                FileUtils.mkdir_p(dir)
                open(file, "w") {|f|} # touch
            else
                File.unlink(file)
            end
            ctx.reply 200
        when "acdir"
            throw "Unauthorized" unless invitee
            dir = hostpath+"/.cache/access/#{invitee}"
            case ctx.queries['m']
            when "r"
                FileUtils.mkdir_p(dir)
                (Dir.new(hostpath).sort - [".", "..", ".cache"]).each { |fn|
                    puts dir+"/#{fn}"
                    open(dir+"/#{fn}", "w") {|f|}
                }
            else
                FileUtils.rm_rf(dir)
            end
            ctx.reply 302, %(Location: http://#{ctx.vars['HOST_ADDR']}/#{(bp+ap).join("/").to_http})
        when "browse"
            out = StringIO.new
            out << "<!DOCTYPE html><html><head><meta http-equiv='content-type' content='text/html; charset=UTF-8' /><meta name='viewport' content='width=device-width, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no'/><title>"
            out << ap.join(" / ").to_html
            out << %(</title></head><body style='font-size:150%;'>)

            out << %(<div style='position:absolute;top:20px;right:20px;float:right;text-align:right;background-color:rgba(255,255,255,0.7);'>)
            if privileged
                out << %([<a href="?invitee=#{"anyone" unless invitee}">#{invitee ? "-" : "+"}</a>])
            end
            out << %(#{ctx.vars['SESSION_HTML']}</div>)

            if invitee
                out << %{<script type="text/javascript">
                    function request (url, msg) {
                        if (window.XMLHttpRequest) {
                            req = new XMLHttpRequest();
                        } else if (window.ActiveXObject) {
                            req = new ActiveXObject("Microsoft.XMLHTTP");
                        }
                        req.open('POST', url, true);
                        req.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
                        req.onreadystatechange = function () {
                            if (req.readyState != 4) return;
                            if (req.status != 200) {
                                alert("Failed to send "+msg);
                            }
                        };
                        req.send(msg);
                    }
                </script>}.htrim
                out << "<div style='background-color:orange;padding:10px;'>"
                out << %{Access control for <b>#{invitee.to_html}</b>.<br/>(change to: <input type='text' name='invitee' onchange='window.location.replace("?invitee="+value);'></input> }
                (Dir.new(hostpath+"/.cache/access").sort -
                        [".", "..", invitee]).each { |e|
                    out << %(<a href="?invitee=#{e.to_http}">#{e.to_html}</a> )
                } if File.directory?(hostpath+"/.cache/access")
                out << ")</div>"
            end

            out2 = []
            out2 << %(<a href="/#{bp.join("/").to_http}">HOME</a>)
            ap.each_index { |i|
                p = (bp+ap[0..i]).join("/").to_http
                if invitee
                    check = checkbox(([@source]+ap[0..i]).join("/"), p, invitee)
                end
                out2 << %(#{check}<a href="/#{p}">#{ap[i].to_html}</a>)
            }
            out2 << %([<a href="/#{(bp+ap).join("/").to_http}?o=acdir&m=r">All</a>|<a href="/#{(bp+ap).join("/").to_http}?o=acdir&m=">Clear</a>]) if invitee
            out << %(<h2>#{out2.join(" / ")}</h2>)

            entries = (Dir.new(hostpath).sort - [".", "..", ".cache"]).find_all { |e| File.exist?(hostpath+"/"+e) }
            unless privileged
                entries = entries.find_all { |e|
                    canread?(hostpath+"/#{e}", user)
                }
            end
            dirs = entries.find_all {|e| File.directory?(hostpath+"/"+e) ||
                    e =~ /\.(pod|url)$/i }
            images = entries.find_all {|e| e =~ /\.(jpeg|jpg|png|gif|bmp)$/i }
            mp3s = entries.find_all {|e| e=~ /\.mp3$/i }
            etc = entries - dirs - images - mp3s

            dirs.each { |e|
                next if e =~ /^\./
                p = (bp+ap+[e]).join("/").to_http
                if invitee
                    check = checkbox(hostpath+"/#{e}", p, invitee)
                end
                out << %(<b>[DIR]</b> #{check}<a href="/#{(bp+ap+[e]).join("/").to_http}">#{e.to_html}</a><br>)
            }

            out << %{
            <script type="text/javascript">
                imagePaths = [ #{images.map{|e|([""]+bp+ap+[e]).join("/").to_http.inspect}.join(", ")} ];
                imageNames = [ #{images.map{|e|"'"+e.to_html.gsub("'","\\'")+"'"}.join(", ")} ];
                function showImage(i) {
                    d = document.getElementById("imageframe");
                    if (i < 0 || i >= imagePaths.length) {
                        d.innerHTML = "";
                        d.style.visibility = "hidden";
                        return;
                    }

                    ihtml = "";
                    ihtml +="<div style='position:absolute;left:2%;top:2%;width:96%;height:96%;background:url("+imagePaths[i]+"?o=thumbnail);background-size:contain;background-repeat:no-repeat;background-position:center center;background-origin:content-box;'></div>";
                    ihtml += "<div style='position:absolute;left:2%;top:2%;width:96%;height:96%;text-align:center;background:url("+imagePaths[i]+");background-size:contain;background-repeat:no-repeat;background-position:center center;background-origin:content-box;'>";
                    ihtml += "<center><a style='color:white;background-color:rgba(0,0,0,0.5);' href='"+imagePaths[i]+"'>"+imageNames[i]+"</a></center></div>";
                    ihtml += "<div style='width:60%;height:90%;position:absolute;top:10%;left:20%;' onclick='showImage(-1);'></div>";
                    ihtml += "<div style='width:20%;height:100%;position:absolute;left:0%;' onclick='showImage("+(i-1)+");'></div>";
                    ihtml += "<div style='width:20%;height:100%;position:absolute;right:0%;' onclick='showImage("+(i+1)+");'></div>";
                    d.innerHTML = ihtml;
                    d.style.visibility = "visible";
                }
            </script>
            <div style="z-index:9999;visibility:hidden;background-color:rgba(0,0,0,0.5);position:fixed;top:0%;bottom:0%;left:0%;right:0%;overflow:hidden;" id="imageframe"></div>
            }.htrim if images.size > 0
            images.each_index { |i|
                e = images[i]
                p = (bp+ap+[e]).join("/").to_http
                abr = e[0...-4]
                if abr.length > 12
                    abr[12..-1] = ""
                end
                #out << %(<div style="position:relative;float:left;height:130px;overflow:hidden;" title="#{e.to_html}"><a href="?p=#{p}">)
                check = checkbox(hostpath+"/#{e}", p, invitee) if invitee
                out << %{
                    <div style="position:relative;float:left;height:130px;overflow:hidden;" title="#{e.to_html}">
                        <a onclick="showImage(#{i});">
                            <image style="padding:1px;" src="/#{p}?o=thumbnail"></image>
                        </a>
                        <div style="color:black;font-size:12px;position:absolute;top:3px;left:3px;">#{check}#{abr.to_html}</div>
                        <a href="/#{p}" style="text-decoration:none"><div style="color:white;font-size:12px;position:absolute;top:2px;left:2px;">#{check}#{abr.to_html}</div></a>
                    </div>
                }.htrim
            }
            out << %(<div style="clear:both;"></div>)

            out << audioPlayer if mp3s.size > 0
            if mp3s.size > 1
                p = (bp+ap).join("/").to_http
                #out << %(<h3><a href="/#{p}?o=playlist">PlayAll</a>)
                out << %(<h3><a href="/#{p}?o=playlist" onclick="return playAudio(href);">PlayAll</a>)
                out << %( (<a href="/#{p}?o=playlistlow" onclick="return playAudio(href);">Low</a>)</h3>)
            end

            mp3s.each_index { |i|
                e = mp3s[i]
                p = (bp+ap+[e]).join("/").to_http
                check = checkbox(hostpath+"/#{e}", p, invitee) if invitee
                out << %(#{check}<a href="/#{p}" onclick="return playAudio(href);">#{e.to_html}</a>)
                out << %( -- (<a href="/#{p}?o=playlistlow" onclick="return playAudio(href);">low</a>))
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
                check = checkbox(hostpath+"/#{e}", p, invitee) if invitee
                out << "<tr>"
                out << %(<td align="right" style="padding-right:10px;">#{sizeh}</td><td><a href="/#{p}">#{check}#{e.to_html}</a></td>)
                out << "</tr>"
            }
            out << %(</table>)
            out << %(<br/>)*2
            out << "</body></html>"

            ctx.reply 200,
                "Cache-Control: no-cache",
                "Pragma: no-cache",
                "Connection: close",
                "Set-Cookie: invitee=#{invitee}; Path=/; HttpOnly",
                "Content-Type: text/html"
            ctx.io.puts out.string
        when "thumbnail"
            throw "Invalid thumbnail path" unless File.file?(hostpath)
            cachedir = File.dirname(hostpath)+"/.cache"
            thumbdir = cachedir+"/thumb"
            thumbfile = thumbdir+"/#{ap.last}"

            unless File.file?(thumbfile)
                FileUtils.mkdir_p(thumbdir)
                open(cachedir+"/lock", "w") { |f|
                    f.flock(File::LOCK_EX)
                    system("convert", "-resize", "128x128", hostpath, thumbfile)
                }
            end

            WebApp::File.new(thumbfile, "image/jpeg").call ctx
        when "browsepodcast"
            out = StringIO.new
            out << "<!DOCTYPE html><html><head><meta http-equiv='content-type' content='text/html; charset=UTF-8' /><title>"
            out << ap.join(" / ").to_html
            out << %(</title></head><body style="font-size:150%;">)

            out2 = []
            out2 << %(<a href="/#{bp.join("/").to_http}">HOME</a>)
            ap.each_index { |i|
                out2 << %(<a href="/#{(bp+ap[0..i]).join("/").to_http}">#{ap[i].to_html}</a>)
            }
            out << %(<h2>#{out2.join(" / ")}</h2>)

            out << audioPlayer

            url = File.read(hostpath).chomp
            # TODO: Could be a security hole.
            xml = REXML::Document.new(`curl -s '#{url}'`.force_encoding("ASCII-8BIT"))
            REXML::XPath.each(xml.root, "//item") { |e|
                l = []
                REXML::XPath.each(e, 'title/text()|enclosure/@url') { |i|
                    l << i.value
                }
                next unless l.size == 2
                out << %(<b>[EPISODE]</b> <a href="#{l[1]}" onclick="#{
                    'return playAudio(href);' if l[1] =~ /\.mp3$/i
                }">#{l[0].to_html}</a><br>)
            }
            out << "<br/>"*2;
            out << "</body></html>"

            ctx.reply 200,
                "Cache-Control: no-cache",
                "Pragma: no-cache",
                "Connection: close",
                "Content-Type: text/html"
            ctx.io.puts out.string
        when "remote"
            url = File.read(hostpath).chomp
            # guess content-type and stream
            ctx.reply 302, %(Location: #{url})
        else
            raise "Unknown operation:#{op}"
        end
    end
end
