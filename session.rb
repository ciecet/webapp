require 'openid'
require 'openid/extensions/ax'
require 'digest/sha1'

class Session

    def initialize app, users, timeout=2*60*60
        @app = app
        @users = users
        @timeout = timeout
        @sessions = {}
    end

    def call ctx
        # Handle authentication
        env = ctx.env
        sid = env["sid"]
        stime = @sessions[sid][:stime] if @sessions.has_key?(sid)
        if stime && (Time.now.to_i - stime) < @timeout
            @app.call ctx
            return
        end

        sess = {}
        env.each { |k,v|
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

            # TODO: MY_URL may contain private queries,
            #       but ruby-openid cannot handle it.
            # redir = r.redirect_url(env["BASE_URL"], MY_URL)
            redir = r.redirect_url(env["BASE_URL"], env["BASE_URL"])

            ctx.reply 302, %(Location: #{redir})
        else
            r = oc.complete(sess, env["BASE_URL"])
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
                "Set-Cookie: sid=#{sid}; HttpOnly",
                %(Location: #{env["BASE_URL"]})
            @sessions[sid] = { :stime => stime, :email => email }
        end
    end
end
