#!/usr/bin/env ruby
#encoding: UTF-8

require "pp"

class Srec
  def initialize(hash={})
    if hash[:file]
      if not File.exist? hash[:file]
        puts "Error: File not found #{hash[:file]}"
        return nil
      end
      @data=IO.read(hash[:file]).gsub(/\r/,"")
    end
    @lines=@data.split "\n"
    @mem={}
    @bytes=0
    @lines.each do |l|
      if l[0]=='S'
        type=l[1].to_i
        len=l[2...4].to_i(16)
        case type
        when 0,1,9,5
          alen=2
        when 2,8,6
          alen=3
        when 3,7
          alen=4
        else
          next
        end
        addr=l[4...4+alen*2].to_i(16)
        dp=4+alen*2
        b=[]
        (len-alen).times do |i|
          b << l[dp+i*2..dp+i*2+1].to_i(16)
        end
        crc= b.pop
        @bytes+=b.size
        #puts "#{type},#{len},#{addr},#{b},crc=#{crc} #{l}"
        if [1,2,3].include? type
          @mem[addr]=b
        elsif [7,8,9].include? type
          @boot=b
        elsif type==0
          @info=b.pack("c*")
        else
          puts "Warning: Unsupported line : #{l}"
        end
      end
    end
    puts "'#{@info}': #{@mem.length} Records, #{@bytes} Bytes"
  end
  def to_blocks min,max,size
    blks={}
    @mem.each do |a,b|
      len=b.size
      len.times do |i|
        if a+i>max or a+i<min
          puts "Error: data out of range #{(a+i).to_s(16)} [#{min.to_s(16)}..#{max.to_s(16)}]"
          next
        end
        blk=(a+i-min)/size
        oset=(a+i-min)%size
        blks[blk]=Array.new(size,0) if not blks[blk]
        blks[blk][oset]=b[i]
      end
    end
    blks
  end
end
