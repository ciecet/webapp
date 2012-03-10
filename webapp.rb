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
    attr_reader :queries, :cookies, :posts, :vars

    def initialize io, env
        @io = io
        @env = env
        @replied = false
        @vars = {}

        qs = env["QUERY_STRING"]
        if qs
            @queries = {}
            qs.split("&").each { |kv|
                (k,v) = kv.split("=",2)
                @queries[k] = WEBrick::HTTPUtils::unescape(v) if v
            }
        end

        hc = env["HTTP_COOKIE"]
        if hc
            @cookies = {}
            hc.split("; ").each { |kv|
                (k,v) = kv.split("=",2)
                @cookies[k] = v if v
            }
        end

        du = WEBrick::HTTPUtils::unescape(env['DOCUMENT_URI']).
                force_encoding("utf-8")
        @vars['APP_PATH'] = du.split("/") - ["", ".", ".."]
        @vars['BASE_PATH'] = []
    end

    def readposts
        return if @posts
        cl = env['CONTENT_LENGTH']
        return unless cl && env['REQUEST_METHOD'] == "POST"

        @posts = {}
        @io.recv(cl.to_i).split("\n").each { |l|
            (k,v) = l.split("=",2)
            @posts[k] = WEBrick::HTTPUtils::unescape(v) if v
        }
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
        @server = TCPServer.new("localhost", port)
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
                    throw "No response from application" unless ctx.replied
                rescue
                    puts $!.message
                    puts $!.backtrace.join("\n")
                    unless ctx.replied
                        ctx.reply 500, "Content-Type: text/html"
                        ctx.io.puts %{
                            <html><title>#{$!.message}</title><body>
                            <h1>500 Internal Server Error</h1>
                            <h2>#{$!.message.to_html}</h2>
                            <pre>#{$!.backtrace.join("\n").to_html}</pre>
                            <h2>Environments:</h2>
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
            <h2>Environments</h2>
            #{ctx.env.map{|k,v|
                "<b>#{k.to_html}</b> = #{v.to_html}"
            }.join("<br>")}
            <h2>Queries</h2>
            #{ctx.queries.map{|k,v|
                "<b>#{k.to_html}</b> = #{v.to_html}"
            }.join("<br>")}
            <h2>Cookies</h2>
            #{ctx.cookies.map{|k,v|
                "<b>#{k.to_html}</b> = #{v.inspect.to_html}"
            }.join("<br>")}
            <h2>Variables</h2>
            #{ctx.vars.map{|k,v|
                "<b>#{k.to_html}</b> = #{v.inspect.to_html}"
            }.join("<br>")}
            </body></html>
        }.htrim
    end
end

class AppMap
    def initialize appmap
        @appmap = {}
        appmap.each {|k,v|
            @appmap[k.split("/") - [""]] = v
        }
    end

    def call ctx
        ap = ctx.vars['APP_PATH']
        bp = ctx.vars['BASE_PATH']
        @appmap.each { |k,v|
            next unless ap[0..k.size-1] == k

            ctx.vars['APP_PATH'] = ap.drop(k.size)
            ctx.vars['BASE_PATH'] = k + bp
            v.call ctx
            return
        }

        throw "No application found for #{(bp+ap).join("/")}"
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
    def initialize hbp
        @hostBasePath = ::File.realpath(hbp)
    end

    def call ctx
        ap = ctx.vars['APP_PATH']
        throw "APP_PATH was determined." unless ap
        bp = ctx.vars['BASE_PATH']

        hostpath = ([@hostBasePath]+ap).join("/")
        urlpath = (bp+ap).join("/")

        unless ::File.directory?(hostpath)
            WebApp::File.new(hostpath).call ctx
            return
        end

        out = StringIO.new
        out << %(<html><head><title>#{urlpath.to_html}</title></head><body>)
        unless ap.empty?
            out << %(<a href="/#{::File.dirname(urlpath).to_http
                }">(Parent Directory)</a><br/>)
        end
        (::Dir.new(hostpath).sort - [".", ".."]).each { |e|
            out << %(<a href="/#{(urlpath+"/"+e).to_http
                }">#{e.to_html}</a><br/>)
        }
        out << %(</body></html>)

        ctx.reply 200, "Content-Type: text/html"
        ctx.io.puts out.string
    end
end

end # module
