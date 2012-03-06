require 'socket'
require 'stringio'
require 'webrick/httputils'

module WebApp

STATUS_MESSAGES = {
    200 => "OK",
    500 => "Internal Server Error",
    206 => "Partial download",
    302 => "Found"
}

class Context
    attr_reader :io, :env, :replied

    def initialize io, env
        @io = io
        @env = env
        @replied = false
    end

    def reply status, *headers
        o = StringIO.new
        o << "Status: #{status} #{STATUS_MESSAGES[status]}\n"
        headers.flatten.each { |h|
            o << h
            o << "\n"
        }
        o << "\n"
        @io.puts o.string
        @replied = true
    end
end

class SCGI
    def initialize port=9000
        @server = TCPServer.new("localhost", 9000)
    end

    def run app=nil, &p
        app = p unless app
        loop do
            Thread.start(@server.accept) { |io|
                begin
                    h = io.recv(10).split(":")
                    h = h[1]+io.recv(h[0].to_i - h[1].size)
                    throw "No trailing comma" unless io.recv(1) == ","
                    ctx = Context.new(io, Hash[*h.split("\0")])
                    app.call ctx
                rescue
                    if ctx.replied
                        puts $!.message
                        puts $!.backtrace.join("\n")
                    else
                        ctx.reply 500, "Content-Type: text/html"
                        ctx.io.puts %{
                            <html><title>#{$!.message}</title><body>
                            <h1>500 Internal Server Error</h1>
                            <h2>#{$!.message.to_html}</h2>
                            <pre>#{$!.backtrace.join("\n").to_html}</pre>
                            <h2>Values:</h2>
                            <pre>#{
                                ctx.env.map{|k,v|"#{k} = #{v}"}.
                                join("\n").to_html
                            }</pre>
                            </body></html>
                        }.htrim
                    end
                ensure
                    io.close
                end
            }
        end
    end
end

class Dump
    def call ctx
        ctx.reply 200, "Content-Type: text/html"
        ctx.io.puts %{
            <html><body>
            #{ctx.env.map{|k,v|
                "<b>#{k.to_html}</b> = #{v.to_html}"
            }.join("<br>")}
            </body></html>
        }.htrim
    end
end

class AppMap
    def initialize appmap
        @appmap = appmap
        @regs = {}
        appmap.each { |k,v|
            @regs[k] = v if Regexp === k
        }
    end

    def call ctx
        urlpath = ctx.env['DOCUMENT_URI']
        app = @appmap[urlpath]
        @regs.each { |k,v|
            next unless urlpath =~ k
            app = v
            break
        }

        if app
            app.call ctx
        else
            throw "No application found at #{urlpath}"
        end
    end
end

class CGI
    def initialize cmd
        @exec = cmd
    end

    def call ctx
        ctx.env['SCRIPT_NAME'] = ctx.env['DOCUMENT_URI']+"/index.cgi"
        pid = Process.spawn(ctx.env, @exec, :in=>'/dev/null', :out=>ctx.io)
        Process.detach(pid)
    end
end

MIME_TYPES = {}
open("/etc/mime.types", "r") { |f| f.each_line {|l|
    l = l.strip.gsub(/#.*/, "").split
    next unless l.size > 1
    l[1..-1].each { |ext|
        MIME_TYPES[ext] = l[0]
    }
}}

class File
    def initialize filepath, mt=nil
        throw "File not found: #{filepath}" unless ::File.file?(filepath)
        @filepath = filepath
        unless mt
            mt = MIME_TYPES[(filepath[/[^.]*$/] || "").downcase]
        end
        unless mt
            IO.popen("file -b --mime-type -f -", "w+") { |f|
                f.puts @filepath
                f.close_write
                mt = f.readline.chomp
            }
        end
        @mimetype = mt || "application/octet-stream"
    end

    def call ctx
        size = ::File.size(@filepath)
        if ctx.env["HTTP_RANGE"] =~ /bytes=([0-9]*)-([0-9]*)(\/(.*))?/
            b = $1.empty? ? 0 : $1.to_i
            e = $2.empty? ? (size-1) : $2.to_i
            ctx.reply 206,
                "Cache-Control: no-cache",
                "Pragma: no-cache",
                "Connection: close",
                "Content-Type: #{@mimetype}",
                "Content-Range: bytes #{b}-#{e}/#{size}",
                "Content-Length: #{e - b + 1}",
                "Accept-Ranges: bytes"
            open(@filepath, "r") {|f|
                IO.copy_stream(f, ctx.io, (e-b+1), b)
            }
        else
            ctx.reply 200, 
                "Cache-Control: no-cache",
                "Pragma: no-cache",
                "Connection: close",
                "Content-Type: #{@mimetype}",
                "Content-Length: #{size}",
                "Accept-Ranges: bytes"
            open(@filepath, "r") {|f|
                IO.copy_stream(f, ctx.io)
            }
        end
    end
end

class Dir
    def initialize hostbase, urlbase=nil
        @hostbase = hostbase.gsub(/\/*$/, "")
        @urlbase = urlbase || "/"
    end

    def call ctx
        urlpath = WEBrick::HTTPUtils::unescape(ctx.env['DOCUMENT_URI']).
                force_encoding("utf-8")
        unless urlpath == @urlbase || urlpath.start_with?(@urlbase+"/")
            throw "Cannot access to #{urlpath}. #{@urlbase}"
        end

        p = urlpath[@urlbase.size..-1].split("/") - ["", ".", ".."]
        hostpath = ([@hostbase]+p).join("/")
        urlpath = ([@urlbase]+p).join("/")

        unless ::File.directory?(hostpath)
            WebApp::File.new(hostpath).call ctx
            return
        end

        out = StringIO.new
        out << %(<html><head><title>#{urlpath.to_html}</title></head><body>)
        unless p.empty?
            out << %(<a href="#{WEBrick::HTTPUtils.escape(
                ::File.dirname(urlpath).force_encoding("ASCII-8BIT"))
                }">(Parent Directory)</a><br/>)
        end
        (::Dir.new(hostpath).sort - [".", ".."]).each { |e|
            out << %(<a href="#{WEBrick::HTTPUtils.escape(
                (urlpath+"/"+e).force_encoding("ASCII-8BIT"))
                }">#{e.to_html}</a><br/>)
        }
        out << %(</body></html>)

        ctx.reply 200, "Content-Type: text/html"
        ctx.io.puts out.string
    end
end

end # module
