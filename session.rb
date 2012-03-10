require 'openid'
require 'openid/extensions/ax'
require 'openid/store/filesystem'
require 'digest/sha1'

class DummySession
    def initialize app, user
        @app = app
        @user = user
    end

    def call ctx
        ctx.vars['SESSION_USER'] = @user
        @app.call ctx
    end
end

class Session

    @@sessions = {}

    def initialize app, users=nil, timeout=2*60*60
        @app = app
        @users = users
        @timeout = timeout
    end

    def call ctx
        burl = %(http://#{ctx.env['HTTP_HOST']}/#{
            ctx.vars['BASE_PATH'].join("/").to_http})
        curl = %(http://#{ctx.env['HTTP_HOST']}/#{
            (ctx.vars['BASE_PATH'] + ctx.vars['APP_PATH']).join("/").to_http})

        # Handle authentication
        sid = ctx.cookies["sid"]
        session = @@sessions[sid]
        if session
            if (Time.now.to_i - session[:stime]) < @timeout
                if @users && !@users.include?(session[:email])
                    throw "Access denied. user:#{session[:email]}"
                end

                ctx.vars['SESSION_USER'] = session[:email]
                @app.call ctx
                return
            end
            @@sessions[sid] = nil
        end

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
                throw "Authentication failed: #{r.message}"
            end
            stime = Time.now.to_i
            sha1 = Digest::SHA1.new
            sha1 << email
            sha1 << stime.to_s
            sha1 << rand.to_s
            sid = sha1.hexdigest

            ctx.reply 302,
                "Set-Cookie: sid=#{sid}; Path=/; HttpOnly",
                %(Location: #{curl})
            @@sessions[sid] = { :stime => stime, :email => email }
        end
    end
end
