# encode: UTF-8

## CORTEXER SSE:::::::::::::

def json_sse_demo request,args,session,event
  if not session or session==0
    return ["text/event-stream",{}]
  end

  if not $sessions[session][:queue]
    $sessions[session][:queue]=Queue.new
    puts "created session queue :)"
    data={
      session: session,
      now:Time.now.to_i,
    }
    return ["text/event-stream",data]
  end
  loops=0
  #pp session
  while loops<10000
    if $sessions[session][:thread] and not $sessions[session][:thread].status
      puts "thread ended"
      data={
        now:Time.now.to_i,
        #rts: $sp.rts,
        #dtr: $sp.dtr,
        #cts: $sp.cts,
        #dsr: $sp.dsr,
        logs: ["Thread ended"]
      }
      $sessions[session][:thread]=nil
      return ["text/event-stream",data]
    end
    if not $sessions[session][:queue].empty?
      logs=[]
      while not $sessions[session][:queue].empty?
        logs<<$sessions[session][:queue].pop.encode("UTF-8", :invalid => :replace, :undef => :replace, :replace => "?")
      end
      #puts "SSE: #{logs}"
      data={
        now:Time.now.to_i,
        #rts: $sp.rts,
        #dtr: $sp.dtr,
        #cts: $sp.cts,
        #dsr: $sp.dsr,
        logs: logs,
      }
      return ["text/event-stream",data]
    end
    sleep 0.001
    loops+=1
  end
  data={
    now:Time.now.to_i,
    #rts: $sp.rts,
    #dtr: $sp.dtr,
    #cts: $sp.cts,
    #dsr: $sp.dsr,

  }
  return ["text/event-stream",data]
end
