def safe_encode str
    str.bytes.map{|i|sprintf("%02x",i)}.join
end

def safe_decode str
    a = []
    str.gsub(/../) { |i| a << i.hex }
    a.pack("c*").force_encoding("utf-8")
end

class String
    HTML_ESCAPES = {
        '&' => '&amp;',
        '"' => '&quot;',
        "'" => '&apos;',
        '<' => '&lt;',
        '>' => '&gt;',
        ' ' => '&nbsp;',
        "\n" => '<br/>'
    }
    def to_html()
        gsub(/&|"|>|<| |'|\n/) { |t| HTML_ESCAPES[t] }
    end
    def to_tex()
        gsub(/_/, "\\_")
    end
    def htrim()
        self.gsub(/\s*\n\s*/, " ")
    end

    HTTP_ESCAPE_CHARS = /([#{Regexp.escape(
        (0x0..0x1f).collect{|c| c.chr }.join + "\x7f"+
        " "+
        '<>#%"'+
        '{}|\\^[]`'+
        (0x80..0xff).collect{|c| c.chr }.join+
        '()'
    )}])/n

    def to_http()
        self.force_encoding("ASCII-8BIT").gsub(HTTP_ESCAPE_CHARS) { |c| "%%%02x"%c.ord}
    end

    def from_http()
        self.gsub(/%([0-9a-fA-F]{2})/) { |c| $1.hex.chr }.force_encoding("utf-8")
    end
end
