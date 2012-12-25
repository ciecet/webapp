require 'stringio'

class TextPager

    PAGE_SIZE = 5000

    def initialize filepath
        throw "File not found: #{filepath}" unless ::File.file?(filepath)
        @filepath = filepath
        @size = File.size(@filepath)
        @numPages = (@size + PAGE_SIZE - 1) / PAGE_SIZE
    end

    def call ctx
        if ctx.queries.has_key? "p"
            page = ctx.queries["p"] || "1"
            pi = page.to_i - 1
            if pi < 0
                page = "1"
                pi = 0
            elsif pi >= @numPages
                page = @numPages.to_s
                pi = @numPages - 1
            end
            content = nil
            open(@filepath, "r") { |f|
                if pi > 0
                    f.seek(pi * PAGE_SIZE - 1)
                    f.gets
                end
                content = (f.read(PAGE_SIZE).force_encoding("UTF-8") +
                        (f.gets || "")).to_html
            }
            ctx.reply 200, 
                "Cache-Control: no-cache",
                "Pragma: no-cache",
                "Connection: close",
                "Content-Type: text/plain",
                "Content-Length: #{content.bytesize}"
            ctx.io.puts content
            return
        end

        ap = ctx.vars['APP_PATH'] - ['.cache']
        out = <<-EOF
<!DOCTYPE html>
<html>
    <head>
        <meta http-equiv='content-type' content='text/html; charset=UTF-8' />
        <meta name='viewport' content='width=device-width, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no'/>
        <title>#{ap.join("/").to_html} (#{page}/#{@numPages})</title>
        <style type="text/css">
            .btn {
                position:fixed;
                background-color:rgba(255,255,0,0.4);
                font-size:200%;
                -moz-border-radius: 15px;
                -webkit-border-radius: 15px;
                -khtml-border-radius: 15px;
                border-radius: 15px;
                padding: 4px 8px 4px 8px;
            }
        </style>
    </head>
    <body style="font-size:110%;">

        <div id="content"></div>

        <div onclick="prevPage()" class="btn" style="left:5%;bottom:5%">#{"<<".to_html}</div>
        <div onclick="jumpPage()" id="pageControl" class="btn" style="left:47%;bottom:5%;"></div>
        <div onclick="nextPage()" class="btn" style="right:5%;bottom:5%">#{">>".to_html}</div>

        <script>
            var content = document.getElementById("content")
            var pageControl = document.getElementById("pageControl")

            var showPage = function (pg) {
                var xhr = new XMLHttpRequest()
                xhr.open("GET", "?p="+pg, false)
                xhr.send()
                content.innerHTML = xhr.responseText + "<br/><br/><br/><br/>"
                window.scrollTo(0,0)
                currentPage = pg
                pageControl.innerHTML = ""+currentPage
            }
            var jumpPage = function () {
                pg = parseInt(prompt("Page Number between 1~#{@numPages}"))
                if (pg > 0 && pg <= lastPage) {
                    showPage(pg)
                }
            }
            var prevPage = function () {
                if (currentPage > 1) {
                    showPage(currentPage - 1)
                }
            }
            var nextPage = function () {
                if (currentPage < lastPage) {
                    showPage(currentPage + 1)
                }
            }
            var lastPage = #{@numPages}
            showPage(1)
        </script>

    </body>
        EOF

        ctx.reply 200, 
            "Cache-Control: no-cache",
            "Pragma: no-cache",
            "Connection: close",
            "Content-Type: text/html",
            "Content-Length: #{out.bytesize}"
        ctx.io.puts out
    end
end
