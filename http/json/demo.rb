# encode: UTF-8

require 'pathname'

def log session,msg
  puts msg
  if session>0 and $sessions[session]
    $sessions[session][:queue] << "#{msg}\n"
  else
    broadcast msg
  end
end

def json_demo request,args,session,event
  begin
    session=args['session'].to_i
    alert=nil
    #puts "ok: #{args}"
    f={}
    act=args['act']
    val=args['val']
    if act=='puts'
      #puts "to st #{val}"
      #log session,"$#{val}"
      $sp.write "#{val}\n"
      f={ok: true}
    else
      #puts "to queue... #{act} #{$sq.empty?}"
      $sq << {act: act}
    end
    return ["text/json",f]
  rescue => e
    pp e.backtrace
    return ["text/json",{alert: "error #{e}"}]
  end
end
