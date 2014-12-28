#!/usr/bin/env ruby
#encoding: UTF-8

require 'json'
require 'serialport'

class IO
  def ready_for_read?
    result = IO.select([self], nil, nil, 0)
    result && (result.first.first == self)
  end
end


class Stm32
  @port=nil
  @dev=nil
  @state=nil
  @@Commands={
    "go"    => 0x21,
    "getid" => 0x02,
  }
  def initialize(hash={})
    puts "init #{hash}"
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
    puts "Open Serial OK!"
  end
  def get_port()
    @port
  end
  def get_dev()
    @dev
  end

  def send_cmd cmd,ack=true
    c=@@Commands[cmd]
    send_buf [c,0xff-c],ack
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

  def send_buf buf,ack=false
    bytes=buf.pack("c*")
    @port.write bytes
    if ack
      ch=wait_char
      if ch
        #printf "send_buf got ack: %02X\n",ch
        return ack
      else
        puts "send_buf no ack!!!!!!!!!!"
        return false
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
    puts "booting"
    delay=0.01
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
        printf("OK: [%02x]", ch )
        sleep delay
      end
      send_buf [0x7f]
      if ch=wait_char
        if ch==0x79
          puts "Booted OK, retries=#{retries}\n"
          @state=:booted
          return true
        else
          puts "Error:got strange ack: %02X\n",ch
        end
      else
        puts "Error: no cmd ack"
      end
      retries+=1
    end
    puts "Error:not booted, gave up\n"
    return false
  end

  def run addr=0x08000000
    puts "running #{addr}"
    if @state!=:booted
      if not boot
        puts "Error: Cannot run, as cannot get booted"
        return nil
      end
    end
    retries=0
    while retries<4 do
      if send_cmd "go"
        if send_addr addr
          if ch=wait_char
            puts "Started Running, retries: #{retries} got #{ch}\n"
            if ch==0
               @state!=:runnign
              return true
            end
          else
            puts "Started Running???, retries: #{retries} -- no start char\n"
          end
        end
      end
      puts "run failed, retry boot and run"
      if not boot
        puts "Error: Cannot run, as cannot get booted"
        return nil
      end
      retries+=1
    end
  end

end
