#!/usr/bin/env ruby
#encoding: UTF-8

require "pp"
require 'socket'
require 'optparse'
require 'yaml'
require 'srec'

$options = {host: "20.20.20.21", port: 3003}
CONF_FILE='/etc/stm32_cli.conf'

$options=$options.merge YAML::load_file(CONF_FILE) if File.exist?(CONF_FILE)
$options=$options.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}


OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [$options]"

  opts.on("-v", "--[no-]verbose", "Run verbosely; creates protocol log on console (false)") do |v|
    $options[:verbose] = v
  end
  opts.on("-d", "--[no-]debug", "Produce Debug dump on verbose log (false)") do |v|
    $options[:debug] = v
  end

  opts.on("-m", "--msg message", "Message to Send") do |v|
    $options[:msg] = v
  end

  opts.on("-f", "--flash fn.srec", "Flash a SREC file") do |v|
    $options[:flash] = v
  end

end.parse!

#puts $options

@clients={}

def server hash={},&sblock
  hash[:mac]="00:00" if not hash[:mac]
  hash[:port]=3003 if not hash[:port]
  @clients[hash[:mac]]={socket: UDPSocket.new,created:Time.now,count_r:0, count_s:0}
  @clients[hash[:mac]][:thread]=Thread.new(hash[:mac]) do |my_mac|
    loop do
      begin
        r,stuff=@clients[my_mac][:socket].recvfrom(2000) #get_packet --high level func!
        ip=stuff[2]
        port=stuff[1]
        #puts "got reply '#{r}' from server #{ip}:#{port} to our mac #{my_mac}"
        pac={
          proto:'U',
          mac: my_mac,
          ip: ip,
          port:port,
          data:r,
        }
        #pp pac
        # received return packet from server!
        if sblock
          sblock.call pac
        end
        #$sp.write pack pac
        @clients[my_mac][:last_r]=Time.now
        @clients[my_mac][:count_r]+=1
       rescue => e
        puts "thread dies..."
        p e
        p e.backtrace
      end
    end
  end
  #pp @clients
end

$done=false
$end=false
$iq=Queue.new
server(mac: "88:88") do |pac|
  #puts "got: #{pac[:data]}"
  $iq << pac[:data]
#  if $end
#    $done=true
#    next
#  end
end
$seq=0;

def api hash={}
  cmd=nil
  retval=nil
  if hash[:act]==:erase
    cmd=sprintf "E%08X",hash[:addr]
  elsif hash[:act]==:quit
    cmd=sprintf "Q"
  elsif hash[:act]==:go
    cmd=sprintf "G"
  elsif hash[:act]==:raw
    cmd=sprintf "%s",hash[:data]
  end
  if cmd
    retries=0
    done=false
    sstart=Time.now.to_f
    while not done and retries<10
      $seq+=1
      s=sprintf "%02X%s",$seq,cmd
      #puts "sending '#{s}'"
      @clients["88:88"][:socket].send(s, 0, $options[:host], $options[:port] )
      start=Time.now.to_f
      while true
        if not $iq.empty?
          ret=$iq.pop
          rseq=ret[0..1].to_i(16)
          if rseq!=$seq
            puts "rseq=#{rseq} != #{$seq}"
          else
            done=true
            retval=ret[2..-1]
            break
          end
        end
        now=Time.now.to_f
        if now-start>3
          puts "Timeout!"
          break
        end
        sleep 0.01
      end
      retries+=1
    end
    if not done
      puts "Failed!"
    else
      #printf "ok in %.2f secs, %d retries\n",Time.now.to_f-sstart,retries
    end
  end
  retval
end

if fn=$options[:flash]
  if not File.file? fn
    puts "Error: File not found '#{fn}'"
    exit
  end
  sstart=Time.now.to_f
  api act: :quit
  s=Srec.new file: fn
  bl=s.to_blocks 0x8000000,0x08020000,0x100
  bl.each do |b,data|
    api act: :erase, addr: b*0x100+0x8000000
  end
  IO.read(fn).gsub(/\r/,"").split("\n").each do |l|
    if l[0..1]=='S3'
      api act: :raw, data: l
    end
  end
  printf "Flash ok in %.2f secs\n",Time.now.to_f-sstart
elsif $options[:msg]
  puts api act: :raw, data: $options[:msg]
end
