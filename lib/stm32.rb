#!/usr/bin/env ruby
#encoding: UTF-8

require 'json'
require 'serialport'
require 'srec'

class IO
  def ready_for_read?
    result = IO.select([self], nil, nil, 0)
    result && (result.first.first == self)
  end
end

def broadcast str
  printf str
end

class Stm32
  @port=nil
  @dev=nil
  @state=nil
  @cpu_info={}
  @debug=true
  @@Clist_def=[0x00,0x01,0x02,0x11,0x21,0x31,0x44,0x63,0x73,0x82,0x92]
  @@Commands={
    get:    {index:0},
    getver: {index:1},
    getid:  {index:2},
    read:   {index:3},
    go:     {index:4},
    write:  {index:5},
    erase:  {index:6},
  }
  @@Cpu_ids={
    0x416 => {
      family: :L1,
      ram_s:0x20000800,
      ram_e:0x20004000,
      flash_s:0x8000000,
      flash_e:0x08020000,
      flash_bsize:0x100,
      serno:0x1ff80050,
      flash_initial:0
      },
    0x413 => {family: :F4,ram_s:0x20002000,ram_e:0x20020000,flash_s:0x8000000,flash_e:0x08100000,flash_blk:16384,serno:0x1fff7a10,flash_initial:0xff},
    }

  def initialize(hash={})
    @clist=@@Clist_def
    @old_srec={} #we assume nothing flashed
    @debug=hash[:debug]
    if not hash[:dev]
      puts "Error: No serial Device??"
      return nil
    end
    if not File.chardev? hash[:dev]
      puts "Error: '#{hash[:dev]}'' is not serial Device??"
      return nil
    end
    begin
      @port = SerialPort.new hash[:dev],115200,8,1,SerialPort::NONE
      #$sp.read_timeout = 100
      @port.flow_control= SerialPort::NONE
      @port.binmode
      @port.sync = true
    rescue => e
      puts "Error: Cannot open serial device: #{e}"
      pp e.backtrace
      return nil
    end
    @dev=hash[:dev]
    puts "Open Serial OK!" if @debug
  end
  def get_port()
    @port
  end
  def get_dev()
    @dev
  end
  def get_state()
    @state
  end

  def set_state(s)
    @state=s
  end

  def get_cpu(k)
    if @cpu_info
      @cpu_info[k]
    else
      false
    end
  end

  def flush_chars tout=0.1
    while ch=wait_char(tout) do
      puts "\nWarning: Flushed #{ch.to_s(16)}\n"
    end
  end

  def send_cmd cmd,ack=true
    if not @@Commands[cmd] or not @@Commands[cmd][:index]
      puts "Error: Unknown command #{cmd}"
    end
    if not c=@clist[@@Commands[cmd][:index]]
      puts "Error: Unsupported command #{cmd}"
    end
    retries=0
    flush_chars 0.001
    while retries<2 do
      ch=send_buf [c,0xff-c],ack
      if ack
        if not ch
          return :tout
        elsif ch== :nack
          printf("SYNC\r\n") if @debug
          send_buf [32],false #synch!
          flush_chars 0.1
        else
          return ch
        end
      else
        return :ack
      end
    end
    :nack
  end

  def send_addr a,ack=true
    buf=[0,0,0,0]
    check=0
    4.times do |i|
      c=a&0xff
      a>>=8
      buf[3-i] = c
      check ^=c
    end
    buf << check
    send_buf buf,ack
  end

  def send_buf_with_check buf,tout=0.1
    check=0
    buf.each do |b|
      check ^=b
    end
    buf << check
    send_buf buf,true,tout
  end

  def send_buf buf,ack=false,tout=0.1
    bytes=buf.pack("c*")
    printf "> "  if @debug
    bytes.split("").each do |ch|
      @port.write ch
      printf("%02X ",ch.ord)  if @debug
      sleep 0.0001
    end
    puts ""  if @debug
    if ack
      ch=wait_char tout
      if ch
        if ch==0x1f
          printf("< NACK: %02X\n",ch)   if @debug
          return nil
        else
          printf("< ACK: %02X\n",ch)  if @debug
          return :ack
        end
        return ch
      else
        puts "< TOUT"
        return nil
      end
    end
    return true
  end

  def wait_char tout=1
    cnt=0
    while cnt<tout*100
      if @port.ready_for_read?
        return @port.readbyte
      end
      sleep 0.01
      cnt+=1
    end
    return nil
  end

  def boot
    retries=0
    delay=0.001
    while retries<10
      #$sp.rts=1 #if retries>5 #power off --really cold boot
      #sleep 0.5
      @port.rts=0 #if retries>5 #power off --really cold boot
      @port.dtr=0
      sleep delay
      @port.flush_input
      @port.flush_output
      @port.rts=0 #power on
      sleep delay
      @port.dtr=1 #reset up -> start to run
      ch=wait_char delay

      if ch and ch==0
        printf("OK: [%02x]", ch )  if @debug
        sleep delay
      end
      send_buf [0x7f]
      if ch=wait_char
        if ch==0x79
          puts "Booted OK, retries=#{retries}\n"   if @debug
          @state=:booted
          return true
        else
          printf "Error:got strange ack: %02X '%c'\n",ch,ch
        end
      else
        puts "Error: no cmd ack"
      end
      retries+=1
      delay*=2
    end
    puts "Error:not booted, gave up\n"
    return false
  end

  def wait_chars len,tout=0.1
    ret=[]
    len.times do
      if ch=wait_char(tout)
        ret << ch
      else
        puts "Warning: Short Data! #{ret}"
        return nil
      end
    end
    return ret
  end

  def cmd c
    boot if @state!=:booted
    puts "cmd: #{c}"  if @debug
    send_cmd c
    if c==:write #no reply expected
      return
    end
    if len=wait_char
      len+=1
      if buf=wait_chars(len)
        if @debug
          printf "len=#{len}:"
          buf.each do |b|
            printf "%02X ",b
          end
          printf "\n"
        end
        if ack=wait_char
          if ack==0x79
            return buf
          else
            puts "Error: no ack for cmd #{c} #{ack}"
          end
        else
          puts "Error: tout at ack for #{c}"
        end
      else
        puts "Error: timeout for #{c}"
      end
    end
  end


  def get_info
    if buf=cmd(:get)
      broadcast "\nBL ver: #{buf[0].to_s(16)}\n"
      @clist=buf[1..-1]
      #puts "Command list updated to #{@clist}"
    end
    if buf=cmd(:getid)
      @cpu=buf[0]*0x100 + buf[1]
      broadcast "Cpu ID: #{@cpu.to_s(16)}\n"
      if @@Cpu_ids[@cpu]
        @cpu_info=@@Cpu_ids[@cpu]
        broadcast(sprintf "Family: %s\n",  @cpu_info[:family])
        broadcast(sprintf "Ram:    %08X .. %08X %5.1fk\n",  @cpu_info[:ram_s],@cpu_info[:ram_e],(@cpu_info[:ram_e]-@cpu_info[:ram_s])/1024.0)
        broadcast(sprintf "Flash:  %08X .. %08X %5.1fk\n",  @cpu_info[:flash_s],@cpu_info[:flash_e],(@cpu_info[:flash_e]-@cpu_info[:flash_s])/1024.0)
        addr=@cpu_info[:serno]
        base=addr&(0xffffff00)
        oset=addr&(0xff)
        buf=read base,oset+0x10
        serno=""
        10.times do |i|
          serno += sprintf("%02X",buf[oset+i])
        end
        @serno=serno
        broadcast "Serno:  '#{serno}'.\n"
      end
    end
  end

  def read addr,len
    if send_cmd(:read)
      if send_addr addr
        ch=send_buf [(len-1),0xff - (len-1)],true
        if buf=wait_chars(len,0.1)
          if @debug
            printf "len=#{len}:"
            buf.each do |b|
              printf "%02X ",b
            end
            printf "\n"
          end
          return buf
        end
      end
    end
    return nil
  end

  def write addr,data
    return(nil) if not data or data==[]
    len=data.length
    if len>0x100
      broadcast "Too big block to write #{len}\n"
      return nil
    end
    if send_cmd(:write)
      if send_addr addr
        list=[data.length-1]
        list+=data
        if ack=send_buf_with_check(list,3)
          #puts "Write Result: #{ack}"
          return ack
        end
      end
    end
    broadcast "Error: Write fails!\n"
    flush_chars # failed write may have produced some nacks
    return nil
  end

  def erase blocks
    return if not blocks or blocks==[]
    list=[blocks.length-1].pack("n").unpack("cc")
    blocks.each do |b|
      list+=[b].pack("n").unpack("cc")
    end
    if send_cmd(:erase)
      if ack=send_buf_with_check(list,3)
        #puts "Erase #{list.size} Pages Result: #{ack}"
        return ack
      end
    end
    return nil
  end

  def go addr=0x08000000
    #printf "try to Run @ %x",addr
    if @state!=:booted
      if not boot
        broadcast "Error: Cannot run, as cannot get booted\n"
        return nil
      end
    end
    retries=0
    while retries<4 do
      if send_cmd :go
        if send_addr addr
          if ch=wait_char
            puts "Started Running, retries: #{retries} got #{ch}\n"  if @debug
            if ch==0
              @state=:running
              return true
            end
          else
            broadcast "Started Running???, retries: #{retries} -- no start char\n"
          end
        end
      end
      broadcast "run failed, retry boot and run\n"
      if not boot
        broadcast "Error: Cannot run, as cannot get booted\n"
        return nil
      end
      retries+=1
    end
    boot #return to bootstrap mode
    return false
  end

  def flash fn
    if @state!=:booted
      if not boot
        broadcast "Error: Cannot flash, as cannot get booted\n"
        return nil
      end
    end
    if not get_cpu(:flash_bsize)
      get_info
    end
    begin
      broadcast "Flashing #{fn}  -- old #{@old_srec.size}\n"
      s=Srec.new file: fn
      bsize=get_cpu(:flash_bsize)
      fs=get_cpu(:flash_s)
      fe=get_cpu(:flash_e)
      bfull=b=s.to_blocks fs,fe,bsize
      broadcast "#{b.size} blocks of #{bsize}\n"
      if @old_srec
        b=Srec::diff b,@old_srec
        broadcast "DIFF: #{b.size} blocks of #{bsize}\n"
      end
      if b.size==0
        broadcast "Nothing to do -- chip is up to date\n"
        return true
      end
      list=[]
      b.each do |blk,data|
        list << blk
      end
      start=Time.now.to_f
      broadcast "Erasing... \n"
      if erase list
        dur=Time.now.to_f-start
        broadcast "Erased in #{dur}s\n"
        @old_srec={}
        cnt=0
        ok=true
        start=Time.now.to_i
        b.each do |blk,data|
          addr=blk*bsize+fs
          if write addr,data
            if cnt%10==0
              printf("\r#{cnt}/#{b.length} %.0f%% ",100.0*cnt/b.length)
              broadcast "."
            end
          else
            broadcast "Error: Write fails at #{addr}\n"
            ok=false
            break
          end
          cnt+=1
        end
        dur=Time.now.to_f-start
        if ok
          broadcast "\nFlashed in #{dur}s\n"
          @old_srec=bfull
          return true
        else
          broadcast "\nFlash Failed\n"
          boot
          get_info
        end
      else
        puts "Error: Erase failed"
      end
    rescue => e
      puts "Error: Flash Failed: #{e}"
      pp e.backtrace
    end
    return nil
  end

end
