#!/usr/bin/ruby

class SendKin
    def sys *args
        system *args or raise "Failed to run #{args.join(" ")}."
    end

    def call ctx
        ctx.reply 200, 
            "Cache-Control: no-cache", 
            "Pragma: no-cache", 
            "Connection: close", 
            "Content-Type: text/javascript"
        begin
            t = ctx.env['t'] or throw "No Title"
            t.gsub!(%r(^\.+|/), "_")
            u = ctx.env['u'] or throw "No URL"

            Dir.mktmpdir { |workdir|
                tpdf = workdir+"/sendkin.pdf"
                tzip = workdir+"/sendkin.zip"
                npdf = workdir+"/#{t}.pdf"

                if u =~ /\.pdf$/i
                    sys('curl', '-o', tpdf, u)
                    t = File.basename(u)
                else
                    # apply instapaper
                    #u = "http://www.instapaper.com/text?u=#{args['u']}"
                    sys("/home/ciecet/bin/hide", "xvfb-run", "wkhtmltopdf", "-q", u, tpdf)
                    #sys(*%w(xvfb-run wkhtmltopdf --page-width 114 --page-height 166 -O Landscape -B 0 -T 0 -L 0 -R 0), u, tpdf)
                end

                sys("mv", tpdf, npdf)
                sys("rm", "-f", tzip)
                sys("zip", "-q", "-m", "-j", tzip, npdf)
                sys("mutt ciecet@free.kindle.com -s convert -a #{tzip} < /dev/null > /dev/null")
                sys("mutt ciecet.ipad@free.kindle.com -s '' -a #{tzip} < /dev/null > /dev/null")

                ctx.io.puts "document.title=document.title.substring(12);"
            }
        rescue
            ctx.io.puts %(alert(#{([$!.to_s, ""]+$!.backtrace).join("\n").inspect});)
        end
    end
end
=begin
javascript:function __func(){var d=document,z=d.createElement('scr'+'ipt'),b=d.body,l=d.location,t=d.title;try{if(!b)throw(0);d.title='(Saving...) '+t;z.setAttribute('src',l.protocol+'//ciecet.home/sendkin?u='+encodeURIComponent(l.href)+'&t='+encodeURIComponent(t));b.appendChild(z);}catch(e){alert('Please wait until the page has loaded.');}}__func()
=end

