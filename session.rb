require 'openid'
require 'openid/extensions/ax'
require 'openid/store/filesystem'
require 'digest/sha1'

class Session

    DEFAULT_TIMEOUT = 30*24*60*60
    DBFILE="/tmp/session.cache"

    @@sessions = {}
    if File.file?(DBFILE)
        @@sessions = eval(File.read(DBFILE))
    end

    def initialize app, users=nil, timeout=DEFAULT_TIMEOUT
        @app = app
        @users = users
        @timeout = timeout
    end

    def save
        File.write(DBFILE, @@sessions.inspect)
    end

    def call ctx
        burl = %(http://#{ctx.env['HTTP_HOST']}/#{
            ctx.vars['BASE_PATH'].join("/").to_http})
        curl = %(http://#{ctx.env['HTTP_HOST']}/#{
            (ctx.vars['BASE_PATH'] + ctx.vars['APP_PATH']).join("/").to_http})

        sid = ctx.cookies["sid"]
        session = @@sessions[sid]

        # ensure session data
        unless sid && session
            sha1 = Digest::SHA1.new
            sha1 << ctx.env['REMOTE_ADDR']
            sha1 << ctx.env['REMOTE_PORT']
            sha1 << rand.to_s
            sid = sha1.hexdigest
            @@sessions[sid] = {:state => :anonymous}
            ctx.reply 302,
                "Set-Cookie: sid=#{sid}; Path=/; Max-Age=#{@timeout}; HttpOnly",
                %(Location: #{curl})
            return
        end

        case session[:state]
        when :anonymous
            if @users || ctx.queries["o"] == "login"
                session[:state] = :trylogin
                ctx.reply 302, %(Location: #{curl})
            else
                ctx.vars['SESSION_HTML'] = %([<a href="?o=login">login by google-id</a>])
                @app.call ctx
            end
        when :authenticated
            if (Time.now.to_i - session[:stime]) < @timeout
                if ctx.queries["o"] == "logout"
                    session[:state] = @users ? :trylogin : :anonymous
                    save
                    ctx.reply 302, %(Location: #{curl})
                else
                    ctx.vars['SESSION_USER'] = session[:user]
                    ctx.vars['SESSION_HTML'] = %([<a href="?o=logout">logout</a>])
                    @app.call ctx
                end
            else
                session[:state] = :trylogin
                ctx.reply 302, %(Location: #{curl})
            end
        when :trylogin
            sess = {}
            ctx.queries.each { |k,v|
                next unless k =~ /^openid\./
                sess[k] = v
            }
            oc = OpenID::Consumer.new(sess, OpenID::Store::Filesystem.new("/tmp/openid"))
            if sess.empty?
                r = oc.begin("https://www.google.com/accounts/o8/id")
                axreq = OpenID::AX::FetchRequest.new
                axreq.ns_alias = 'ext1'
                axreq.add(OpenID::AX::AttrInfo.new('http://axschema.org/contact/email','email',true))
                r.add_extension(axreq)

                redir = r.redirect_url(burl, curl)
                ctx.reply 302, %(Location: #{redir})
            else
                r = oc.complete(sess, curl)
                email = sess["openid.ext1.value.email"]
                unless OpenID::Consumer::SuccessResponse === r &&
                        (!@users || @users.include?(email))
                    session.replace :state => :anonymous
                    throw "Authentication failed: #{r.message}"
                end

                session[:stime] = Time.now.to_i
                session[:user] = email
                session[:state] = :authenticated
                save
                ctx.reply 302, %(Location: #{curl})
            end
        else
            throw "Invalid session state."
        end
    end
end
