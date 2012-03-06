require 'webrick/httputils'

class HttpEnv
    def initialize app
        @app = app
    end

    def call ctx
        env = ctx.env
        (env["HTTP_COOKIE"] || "").split("; ").each { |kv|
            (k,v) = kv.split("=",2)
            env[k] = v if v
        }
        (env["QUERY_STRING"] || "").split("&").each { |kv|
            (k,v) = kv.split("=",2)
            env[k] = WEBrick::HTTPUtils::unescape(v) if v
        }
        cl = env['CONTENT_LENGTH']
        if cl && env['REQUIRE_METHOD'] == "POST"
            ctx.io.recv(cl.to_i).split("\n").each { |l|
                (k,v) = l.split("=",2)
                env[k] = WEBrick::HTTPUtils::unescape(v) if v
            }
        end

        url = %(http://#{env["HTTP_HOST"]})
        env["BASE_URL"] = url + env["DOCUMENT_URI"].gsub(/\/$/,"")
        env["MY_URL"] = url + env["REQUEST_URI"]

        @app.call ctx
    end
end
