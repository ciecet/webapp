#!/usr/bin/ruby -Ku

$: << "."
require 'util'
require 'webapp'
require 'httpenv'
require 'session'
require 'mediabrowser'
require 'sendkin'

mbrowser = MediaBrowser.new "/home/ciecet/media",
    ["굿모닝 팝스"] => [:podcast, "http://tune.kbs.co.kr/rss/1.xml"],
    ["나꼼수"] => [:podcast, "http://old.ddanzi.com/appstream/ddradio.xml"],
    ["시사 포커스"] => [:podcast, "http://minicast.imbc.com/PodCast/pod.aspx?code=1000674100000100000"],
    ["최진기의 인문특강"] => [:podcast, "http://rss.ohmynews.com/rss/podcast_cjk_online_main.xml"],
    ["컬투쇼"] => [:podcast, "http://wizard2.sbs.co.kr/w3/podcast/V0000328482.xml"],
    ["English as Second Lang"] => [:podcast, "http://feeds.feedburner.com/EnglishAsASecondLanguagePodcast"],
    ["Listen & Play"] => [:podcast, "http://downloads.bbc.co.uk/podcasts/radio/listenplay/rss.xml"],
    ["office"] => [:remote, "http://192.168.10.3/media"]

users = ["ciecet@gmail.com", "okie9090@gmail.com"]

map = WebApp::AppMap.new \
    "/media" => HttpEnv.new(Session.new(mbrowser, users)),
    "/sendkin" => HttpEnv.new(SendKin.new)
#    %r(/src(/.*)?) => WebApp::Dir.new("/home/ciecet/media", "/src")
#    "/test" => WebApp::File.new("test.html")

WebApp::SCGI.new(9000).run map
