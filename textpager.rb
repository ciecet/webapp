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

        <div id="prevBtn" class="btn" style="left:5%;bottom:5%">#{"<<".to_html}</div>
        <div onclick="jumpPage()" id="pageControl" class="btn" style="left:47%;bottom:5%;"></div>
        <div id="nextBtn" class="btn" style="right:5%;bottom:5%">#{">>".to_html}</div>

        <script>
            var content = document.getElementById("content")
            var pageControl = document.getElementById("pageControl")
            var pages = []
            var xhr, currentPage

            var loadPage = function (pg, cb) {
                var page = pages[pg]
                if (page) {
                    cb(page)
                    return
                }

                if (xhr) return
                xhr = new XMLHttpRequest()
                xhr.open("GET", "?p="+pg)
                xhr.onreadystatechange = function () {
                    var req = xhr
                    if (req.readyState != 4) return;
                    xhr = undefined
                    if (req.status == 200) {
                        page = req.responseText
                        pages[pg] = page
                        cb(page)
                        return
                    }
                    cb("Failed to load page")
                }
                xhr.send()
            }
            var updatePage = function () {
                var pg = currentPage
                loadPage(pg, function(txt) {
                    if (pg !== currentPage) {
                        updatePage()
                        return
                    }
                    content.innerHTML = txt + "<br/><br/><br/><br/>"
                    window.scrollTo(0,0)
                })
            }
            var showPage = function (pg) {
                if (pg === currentPage) return
                currentPage = pg
                pageControl.innerHTML = currentPage
                updatePage()
            }
            var jumpPage = function () {
                pg = parseInt(prompt("Page Number between 1~#{@numPages}"))
                if (pg > 0 && pg <= lastPage) {
                    showPage(pg)
                }
            }
            var prevPage = function (e) {
                if (currentPage > 1) {
                    showPage(currentPage - 1)
                }
                if (e) {
                    e.preventDefault()
                }
            }
            var nextPage = function (e) {
                if (currentPage < lastPage) {
                    showPage(currentPage + 1)
                }
                if (e) {
                    e.preventDefault()
                }
            }
            window.addEventListener("keydown", function (e) {
                if (e.keyIdentifier === "Left") {
                    prevPage()
                } else if (e.keyIdentifier === "Right") {
                    nextPage()
                }
            }, true)
            var prevBtn = document.getElementById("prevBtn")
            prevBtn.addEventListener("click", prevPage, true)
            prevBtn.addEventListener("touchstart", prevPage, true)
            var nextBtn = document.getElementById("nextBtn")
            nextBtn.addEventListener("click", nextPage, true)
            nextBtn.addEventListener("touchstart", nextPage, true)
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
