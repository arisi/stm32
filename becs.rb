require "pp"
require 'RMagick'
include Magick

MX=48
MY=36
$data=[]

def in_edge? x,y
  x==0 or x==MX or y==0 or y==MY
end

def in_object? x,y
  x>=7 and x<=22 and y>=9 and y<=15
end

for x in 0..MX
  $data[x]=[]
  for y in 0..MY
    $data[x][y]=75.0
  end
end

def set_conductors
  for y in 0..MY
    for x in 0..MX
      if in_edge? x,y
        $data[x][y]=50.0
      elsif in_object? x,y
        $data[x][y]=100.0
      end
    end
  end
end

def print_data d
  for y in 0..MY
    for x in 0..MX
      if d[x][y]==100
        printf " %3d ",d[x][y]
      else
        printf "%4.1f ",d[x][y]
      end
    end
    puts ""
  end
  puts "\n"
end

def calc_delta d1,d2
  dsum=0
  for y in 0..MY
    for x in 0..MX
      dsum+=(d1[x][y]-d2[x][y]).abs
    end
  end
  dsum
end

def clone d
  n=[]
  n
end

set_conductors
for i in 0..300
  $odata=[]
  for x in 0..MX
    $odata[x]=[]
    for y in 0..MY
      $odata[x][y]=$data[x][y]
    end
  end
  for y in 1..MY-1
    for x in 1..MX-1
      avg=($data[x-1][y]+$data[x+1][y]+$data[x][y-1]+$data[x-1][y+1])/4
      $data[x][y]=avg
    end
  end
  set_conductors
  delta=calc_delta $odata,$data
  printf "%d: delta=%.1f\n",i,delta
  break if delta<0.1
end

print_data $data

M=16
f = Image.new((MX+1)*M, (MY+1)*M) { self.background_color = "white" }
min=nil
max=nil
for x in 0..MX
  for y in 0..MY
    v=$data[x][y]
    min=v if not min or v<min
    max=v if not max or v>max
  end
end

puts min,max
for x in 0..MX
  for y in 0..MY
    rect = Magick::Draw.new
    rect.fill_opacity(1)
    r=255*(($data[x][y]-min)/(max-min))
    b=255-255*(($data[x][y]-min)/(max-min))
    col=sprintf "#%02X%02X%02X",r,0,b
    rect.fill_color(col)
    rect.rectangle(M*x,M*y,M*x+M-1,M*y+M-1)
    rect.draw f
  end
end
puts "12:"
for x in 0..MX
  printf "%.1f ",$data[x][12]
end
f.display
