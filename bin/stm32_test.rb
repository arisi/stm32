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
if stm.boot
  printf "BOOTED OK!\r\n>"
else
  puts "Error: Boot failed! retry!\r\n"
end

#pp stm.run
port=stm.get_port
$stdout.sync = true
oldstate=:unknown
oldaddr=0x08000000
begin
  state = `stty -g`
  loop do
    curstate=stm.get_state
    if oldstate!=curstate
      if curstate==:running
        system("stty raw -echo -icanon isig") # turn raw input on
      else
        system "stty #{state}" # turn raw input off
      end
      oldstate=curstate
    end
    if port.ready_for_read?
      ch = port.readbyte
      if ch==0x0a and stm.get_state==:running
        printf "\n\r"
      elsif ch==0x0d and stm.get_state==:running

      elsif ch>0x1f and stm.get_state==:running
        printf "%c",ch
      else
        printf "[%02x]",ch
      end
    elsif $stdin.ready?
      if curstate==:running  #terminal mode
        c = $stdin.getc
        if c.ord==0x02
          system "stty #{state}" # turn raw input off
          if stm.boot
            printf "BOOTED OK!\r\n>"
          else
            puts "Error: Boot failed! retry!\r\n"
          end
          #system("stty raw -echo -icanon isig") # turn raw input on
        else
          port.write c
        end
      else #debugger
        c = $stdin.gets.chop
        a=c.split " "
        if a[0]=="go"
          if stm.run
            puts "RUN OK!\r\n"
          else
            puts "Error: Run failed! retry!\r\n"
          end
          system("stty raw -echo -icanon isig") # turn raw input on
        elsif a[0]=="id"
          puts "\nGet:"
          stm.get_info
          stm.get_id
          #system("stty raw -echo -icanon isig") # turn raw input on
        elsif a[0]=="dmp"
          if a[1]
            addr=a[1].hex
          else
            addr=oldaddr
          end
          if a[2]
            len=a[2].hex
          else
            len=0x100
          end
          buf=stm.read addr,len
          #printf "0x%08X:",addr
          buf.each_with_index do |b,i|
            if i&0xf==0x0
              printf "\n0x%08X:  ",addr+i
            end
            printf "%02X ",b
          end
          printf "\n";
          oldaddr=addr
          #system("stty raw -echo -icanon isig") # turn raw input on
        else
          puts "Commands: go,id"
        end
        printf "\r\n>"
      end
    else
      sleep 0.01
    end
  end
ensure
  system "stty #{state}" # turn raw input off
end
