#!/usr/bin/env ruby
#encoding: UTF-8

require 'optparse'
require 'yaml'
require 'pp'

require 'io/wait'

local=false
if File.file? './lib/stm32.rb'
  require './lib/stm32.rb'
  puts "using local lib"
  local=true
else
  require 'stm32'
end

options = {}
CONF_FILE='/etc/stm32.conf'

options=options.merge YAML::load_file(CONF_FILE) if File.exist?(CONF_FILE)
options=options.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}

options[:dev] =  "/dev/ttyUSB0" if not options[:dev]
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on("-v", "--[no-]verbose", "Run verbosely; creates protocol log on console (false)") do |v|
    options[:verbose] = v
  end
  opts.on("-d", "--[no-]debug", "Produce Debug dump on verbose log (false)") do |v|
    options[:debug] = v
  end

  opts.on("--dev dev", "serial device to use (/dev/ttyUSB0)") do |v|
    options[:dev] = v
  end
end.parse!

pp options

stm=Stm32.new options

pp stm.get_port()
#stm.boot()
pp stm.run
port=stm.get_port
$stdout.sync = true
begin
  state = `stty -g`
  system("stty raw -echo -icanon isig") # turn raw input on
  loop do
    if port.ready_for_read?
      ch = port.readbyte
      if ch==0x0a
        printf "\n\r"
      elsif ch==0x0d
      elsif ch>0x1f
        printf "%c",ch
      else
        printf "[%02x]",ch
      end
    elsif $stdin.ready?
      c = $stdin.getc
      port.write c
    else
      sleep 0.01
    end
  end
ensure
  system "stty #{state}" # turn raw input off
end
