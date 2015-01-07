#!/usr/bin/env ruby
#encoding: UTF-8

require 'optparse'
require 'yaml'
require 'pp'
#require 'p3'

require 'io/wait'

local=false
require 'srec'

if File.file? './lib/stm32.rb'
  require './lib/stm32.rb'
  puts "using local lib"
  local=true
else
  require 'stm32'
end

if File.file? '../p3/lib/p3.rb'
  require '../p3/lib/p3.rb'
  puts "using local p3 lib"
  local=true
else
  require 'p3'
end

def isprint(c)
  /[[:print:]]/ === c.chr
end

$p=P3.new do |pac|
  # this is run when we get packet from server
  broadcast "we got packet! #{pac}\n"
  pp $p.pack pac
  $sp.write $p.pack pac
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
  opts.on('-f',"--flash file", "S-record file to flash") do |v|
    options[:flash] = v
  end
  opts.on('-g',"--go", "boot and run") do |v|
    options[:go] = true
  end

  opts.on("-h", "--http port", "Http port for debug/status JSON server (false)") do |v|
    options[:http_port] = v.to_i
  end


end.parse!

$sq=Queue.new
if options[:http_port]
  puts "Loading Http-server.. hold on.."
  require 'minimal-http-ruby'
  if local
    minimal_http_server http_port: options[:http_port], http_path:  './http/'
  else
    minimal_http_server http_port: options[:http_port], http_path:  File.join( Gem.loaded_specs['stm32'].full_gem_path, 'http/')
  end
  puts "\n"
  def broadcast str
    return if str==""
    print str
    str=str.gsub(/\r/,"")
    $sessions.each do |s,data|
      $sessions[s][:queue] << str
    end
  end
  sleep 1
else
  def broadcast str
    printf str
  end
end



#pp options

$stm=stm=Stm32.new options

$sp=stm.get_port()
if options[:flash] or options[:go]
  if stm.boot
    stm.get_info
    if options[:flash]
      if stm.flash options[:flash]
        if stm.run
          broadcast "RUNNING OK!\n\n"
        end
      end
    else
      if options[:go]
        if stm.run
          broadcast "RUNNING OK!\n\n"
        end
      else
        broadcast "BOOTED OK!\r\n>"
      end
    end
  else
    puts "Error: Boot failed! retry!\r\n"
  end
else
  stm.set_state :running #assume it is running..
end

#pp stm.run
port=stm.get_port
$stdout.sync = true
oldstate=:unknown
oldaddr=0x08000000
@bufo=""
silent=0
$state = `stty -g`

def do_go stm
  if stm.go
    broadcast "GO OK!\n"
  else
    broadcast "Error: Go failed! retry!\n"
  end
end

def do_boot stm
  system "stty #{$state}" # turn raw input off
  if stm.boot
    broadcast "\n\nBOOTED OK!\n>"
  else
    broadcast "Error: Boot failed! retry!\n"
  end
end

begin
  loop do
    curstate=stm.get_state
    if oldstate!=curstate
      if curstate==:running
        system("stty raw -echo -icanon isig") # turn raw input on
      else
        system "stty #{$state}" # turn raw input off
      end
      oldstate=curstate
    end
    if port.ready_for_read?
      begin
        ch = port.readbyte
      rescue
        next
      end
      if not $p.inchar(ch.ord)
        if ch==0x0a and stm.get_state==:running
          @bufo+= "\n\r"
        elsif ch==0x0d and stm.get_state==:running

        elsif ch>0x1f and stm.get_state==:running
          @bufo+=ch.chr
        else
          @bufo+=sprintf("[%02x]",ch)
        end
      end
    else
      if (silent>5 and @bufo!="") or (@bufo.size>10)
        broadcast @bufo
        #printf @bufo
        @bufo=""
        silent=0
      end
      silent+=1
      if $stdin.ready?
        if curstate==:running  #terminal mode
          c = $stdin.getc
          if c.ord==0x02
            do_boot(stm)
            #system("stty raw -echo -icanon isig") # turn raw input on
          else
            port.write c
          end
        else #debugger
          c = $stdin.gets.chop
          a=c.split " "
          if a[0]=="g"
            do_go stm
            #system("stty raw -echo -icanon isig") # turn raw input on
          elsif a[0]=="i"
            stm.get_info
          elsif a[0]=="e"
            if a[1]
              b=a[1].hex
            else
              b=0
            end
            stm.erase [b]
          elsif a[0]=="w" or a[0]=="wf"
            if a[1]
              addr=a[1].hex
            else
              addr=oldaddr
            end
            if a[2]
              data=[a[2].to_i,0x11,0x22,0x33]
            else
              data=[1,2,3,4]
            end
            addr |= 0x08000000 if a[0]=="wf"
            stm.write addr,data
            oldaddr=addr
          elsif a[0]=="f" and options[:flash]
            stm.flash(options[:flash])
          elsif a[0]=="q"
            break
          elsif a[0]=="r" or a[0]=="rf"
            if a[1]
              addr=a[1].hex
            else
              addr=oldaddr
            end
            addr |= 0x08000000 if a[0]=="rf"
            if a[2]
              len=a[2].hex
            else
              len=0x100
            end
            buf=stm.read addr,len
            #printf "0x%08X:",addr
            if not buf
              broadcast "Illegal address!\n"
            else
              buf.each_with_index do |b,i|
                if i&0xf==0x0
                  broadcast(sprintf("\n0x%08X:  ",addr+i) )
                end
                broadcast(sprintf("%02X ",b))
              end
              broadcast "\n";
              oldaddr=addr
            end
            #system("stty raw -echo -icanon isig") # turn raw input on
          else
            broadcast "Commands: g(o), i(d), w(rite) addr data, r(ead) addr len, e(rase) blk, f(lash) fn, q(uit)"
          end
          broadcast "\r\n>"
        end
      elsif not $sq.empty?
        begin
          act=$sq.pop
          #puts "\ngot #{act}"
          if act[:act]=="go"
            do_go stm
          elsif act[:act]=="flash"
            stm.flash "/home/arisi/projects/mygit/arisi/ctex/bin/sol_STM32L_mg11.srec"
            stm.go
          elsif act[:act]=="boot"
            do_boot(stm)
         elsif act[:act]=="id"
            stm.get_info
          end
          broadcast "\r\n>"
        rescue => e
          puts "queue found error:",e
        end
      else
        sleep 0.01
      end
    end
  end
ensure
  system "stty #{$state}" # turn raw input off
end
