# A script to export all records from the Sitelutions service through their API.
#
# API information and documentation:
# https://sitelutions.com/info/api
#
# NOTE:
# You will need their Premium DNS service in order to use the API.
#
# I am not affiliated with the company in any way myself, I just 
# wanted to put this script out there if anyone else finds it useful.
#
# Copyright (c) 2014 Antti Hukkanen
# License: See the LICENSE document
#
# Usage:
# ruby export.rb your.sitelutions@email.com outfile.zones

require 'io/console'
require 'savon'

username = ARGV[0]
outfile = ARGV[1]

def out(string)
  if $outfile
    $outfile.write(string + "\n")
  else
    puts string
  end
end

def progress(string)
  # We'll only display progress information when the output is saved into
  # a file because in the other case, the progress information can be read
  # straight from the output.
  if $outfile
    puts string
  end
end

def api_client(hdr)
  client = Savon.client do
    endpoint "https://api.sitelutions.com/soap-api"
    namespace "https://api.sitelutions.com/API"
    ssl_verify_mode :none
    headers hdr
  end
end

if username.nil?
  raise "No username given."
end

# print does not generate a newline
print "Password: "
password = STDIN.noecho(&:gets).chomp
puts ""

# The Sitelutions API requires the SOAPAction to be defined in the header
# and at least the current version of savon (2.7.2) does not allow specifying
# the headers separately for each request. Also, there is now way in that
# version of savon to change the client globals once they are defined after
# the initialization. Therefore, we need two separate clients to do two
# separate kinds of requests.
client = api_client({"SOAPAction" => "https://api.sitelutions.com/API#listDomains"})
client_rr = api_client({"SOAPAction" => "https://api.sitelutions.com/API#listRRsByDomain"})

response = client.call :list_domains, message: {user: username, password: password}

# Open the outfile only after we get the first successful API response.
# This way we don't end up with an empty output file if there is an error
# connecting to the API (e.g. incorrect credentials).
if outfile
  $outfile = File.new(outfile, "w")
end

index = 0
response.body[:list_domains_response][:array][:item].each do |domain|
  progress "Exporting " + domain[:name]
  
  out "" if index > 0
  out ";; ZONE - " + domain[:name] + " ;;"
  out ";; EXPIRES: " + domain[:expires]
  out "$ORIGIN " + domain[:name]
  out "$TTL " + domain[:ttl]
  
  # Make SOA record for the domain
  out domain[:name] + ". IN SOA " + domain[:ns] + " " + domain[:mbox] + " ( " + domain[:serial] + " " + domain[:refresh] + " " + domain[:retry] + " " + domain[:expire] + " " + domain[:ttl] + " )"
  out ""
  
  # Fetch all the records for this domain and print them out properly
  redirects = []
  records_response = client_rr.call "listRRsByDomain", message: {user: username, password: password, domainid: domain[:id]}
  records_response.body[:list_r_rs_by_domain_response][:array][:item].each do |record|
    if record[:type] == 'REDIRECT'
      redirects.push(["http://" + record[:fullname] + "/", record[:data]])
    else
      data = record[:data]
      if record[:type] == 'MX' || record[:type] == 'SRV'
        data = record[:aux] + " " + data
      end
      # SOA-type records are not supported by Sitelutions currently but
      # they might become available some time in the future
      if record[:type] == 'TXT' || record[:type] == 'SOA'
        data = '"' + data + '"'
      end
      out record[:fullname] + ". " + record[:ttl] + " IN " + record[:type] + " " + data
    end
  end
  
  if redirects.length > 0
    out ""
    out ";; DOMAIN REDIRECTS - " + domain[:name] + " ;;"
    redirects.each do |redirect|
      out "; REDIRECT: " + redirect[0] + " => " + redirect[1]
    end
  end
  
  # A newline before starting the next domain
  out ""
  
  index += 1
end

if $outfile
  $outfile.close
end

progress "Done"
