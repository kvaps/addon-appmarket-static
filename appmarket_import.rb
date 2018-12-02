#!/usr/bin/env ruby

# -------------------------------------------------------------------------- #
# Copyright 2002-2018, OpenNebula Project, OpenNebula Systems                #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
# -------------------------------------------------------------------------- #

require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'rexml/document'

class OneMarket
    ONE_MARKET_URL = 'http://marketplace.opennebula.systems/'
    AGENT          = 'Market Driver'
    VERSION        = ENV['VERSION']

    def initialize(url, dir)
        @url   = url || ONE_MARKET_URL
        @dir   = dir || 'appliances'
        @agent = "OpenNebula #{VERSION} (#{AGENT})"
    end

    def get(path)

        # Get proxy params (needed for ruby 1.9.3)
        http_proxy = ENV['http_proxy'] || ENV['HTTP_PROXY']

        if http_proxy
            p_uri   = URI(http_proxy)
            p_host  = p_uri.host
            p_port  = p_uri.port
        else
            p_host  = nil
            p_port  = nil
        end

        uri = URI(@url + path)
        req = Net::HTTP::Get.new(uri.request_uri)

        req['User-Agent'] = @agent

        response = Net::HTTP.start(uri.hostname, uri.port, p_host, p_port) {|http|
            http.request(req)
        }

        if response.is_a? Net::HTTPSuccess
            return 0, response.body
        else
            return response.code.to_i, response.msg
        end
    end

    def get_appliances()
        rc, body = get('/appliance')

        if rc != 0
            return rc, body
        end

        applist     = JSON.parse(body)
        app_dir          = ""
        app_conf         = ""
        apptemplate_conf = ""
        vmtemplate_conf  = ""

        Dir.mkdir(@dir) unless File.exists?(@dir)

        puts "Processing appliances"
        applist['appliances'].each { |app|
            id     = app["_id"]["$oid"]
            source = app["files"][0]["url"]

            tmpl = ""

            print_var(tmpl, "NAME",        app["name"])
            print_var(tmpl, "SOURCE",      source)
            print_var(tmpl, "IMPORT_ID",   id)
            print_var(tmpl, "ORIGIN_ID",   "-1")
            print_var(tmpl, "TYPE",        "IMAGE")
            print_var(tmpl, "PUBLISHER",   app["publisher"])
            print_var(tmpl, "FORMAT",      app["format"])
            print_var(tmpl, "DESCRIPTION", app["short_description"])
            print_var(tmpl, "VERSION",     app["version"])
            print_var(tmpl, "TAGS",        app["tags"].join(', '))
            print_var(tmpl, "REGTIME",     app["creation_time"])

            app_dir = "#{@dir}/#{id}"
            puts app_dir
            Dir.mkdir(app_dir) unless File.exists?(app_dir)

            if !app["files"].nil? && !app["files"][0].nil?
                file = app["files"][0]
                size = 0

                if (file["size"].to_i != 0)
                    size = file["size"].to_i / (2**20)
                end

                print_var(tmpl, "SIZE", size)
                print_var(tmpl, "MD5",  file["md5"])

                tmpl64 = ""
                print_var(tmpl64, "DEV_PREFIX", file["dev_prefix"])
                print_var(tmpl64, "DRIVER",     file["driver"])
                print_var(tmpl64, "TYPE",       file["type"])

                if !tmpl64.empty?
                    File.open(app_dir + "/apptemplate.conf", 'w') { |file| file.write(tmpl64) }
                end
            end

            begin
            if !app["opennebula_template"].nil?
                vmtmpl64 = template_to_str(JSON.parse(app["opennebula_template"]))
                File.open(app_dir + "/vmtemplate.conf", 'w') { |file| file.write(vmtmpl64) }
            end
            rescue
            end

            File.open(app_dir + "/app.conf", 'w') { |file| file.write(tmpl) }

        }
    end

    private

    def print_var(str, name, val)
        return if val.nil?
        return if val.class == String && val.empty?

        val.gsub!('"','\"') if val.class == String

        str << "#{name}=\"#{val}\"\n"
    end

    def template_to_str(thash)
        thash.collect do |key, value|
            next if value.nil? || value.empty?

            str = case value.class.name
            when "Hash"
                attr = "#{key.to_s.upcase} = [ "

                attr << value.collect do |k, v|
                     next if v.nil? || v.empty?
                     "#{k.to_s.upcase}  =\"#{v.to_s}\""
                end.compact.join(",")

                attr << "]\n"
            when "String"
                "#{key.to_s.upcase} = \"#{value.to_s}\""
            end
        end.compact.join("\n")
    end
end

################################################################################
# Main Program. Outpust the list of marketplace appliances
################################################################################

url = ENV['MARKETPLACE']
dir = ARGV[0] rescue nil
#if ARGV[0].to_s.empty?
#    dir = "appliances"
#else
#    dir = ARGV[0] rescue nil
#end

one_market = OneMarket.new(url, dir)
one_market.get_appliances
