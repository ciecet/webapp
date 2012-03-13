#!/usr/bin/ruby -Ku

$: << "."
require 'webapp'
require 'session'
require 'mediabrowser'
require 'sendkin'

users = ["ciecet@gmail.com", "okie9090@gmail.com"]

map = WebApp::AppMap.new \
    "/test" => WebApp::Dump.new,
    "/doc" => Session.new(WebApp::Dir.new("/home/ciecet/doc"), users),
    "/media" => Session.new(MediaBrowser.new("/home/ciecet/media", users)),
    "/sendkin" => SendKin.new

WebApp::SCGI.new(9000).run map
