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
        self.gsub(/\s*\n\s*/, "")
    end
end
