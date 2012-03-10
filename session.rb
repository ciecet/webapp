require 'openid'
require 'openid/extensions/ax'
require 'digest/sha1'

class Session

    @@sessions = {}

    def initialize app, users, timeout=2*60*60
        @app = app
        @users = users
        @timeout = timeout
    end

    def call ctx
        curl = %(http://#{ctx.env['HTTP_HOST']}/#{
            (ctx.vars['BASE_PATH'] + ctx.vars['APP_PATH']).join("/").to_http})

        # Handle authentication
        sid = ctx.cookies["sid"]
        session = @@sessions[sid]
        if session
            if (Time.now.to_i - session[:stime]) < @timeout &&
                    @users.include?(session[:email])
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
        oc = OpenID::Consumer.new(sess, nil)
        if sess.empty?
            r = oc.begin("https://www.google.com/accounts/o8/id")
            axreq = OpenID::AX::FetchRequest.new
            axreq.ns_alias = 'ext1'
            axreq.add(OpenID::AX::AttrInfo.new('http://axschema.org/contact/email','email',true))
            r.add_extension(axreq)

            redir = r.redirect_url(curl, curl)
            ctx.reply 302, %(Location: #{redir})
        else
            r = oc.complete(sess, curl)
            email = sess["openid.ext1.value.email"]
            unless OpenID::Consumer::SuccessResponse === r &&
                    @users.include?(email)
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
