
now=0
xx=123
session=null

sse_data = (data) ->
  #console.log "sse:",data
  obj=$("#rightcolumn")
  if data.logs
    arr=obj.html().split("\n")
    if arr.length>100
      obj.html("")
    #console.log arr
    for l in data.logs
      obj.append(l)
    obj.scrollTop($("#rightcolumn")[0].scrollHeight);
  if data.session
    session=data.session
    obj.append "GOT SESSION:#{session}\n"


ajax_data = (data) ->
  console.log "ajax:",data
  $(".adata").html(data.now)


@ajax = (obj) ->
  console.log "doin ajax"
  $.ajax
    url: "/demo.json"
    type: "GET"
    dataType: "json",
    contentType: "application/json; charset=utf-8",
    success: (data) ->
      ajax_data(data)
      setTimeout (->
        ajax()
        return
      ), 3000
      return
    error: (xhr, ajaxOptions, thrownError) ->
      alert thrownError
      return


@stm_port = (act,val) ->
  console.log "port #{act},#{val}"
  if true
    $.ajax(
      url: "/demo.json"
      data:
        act: act
        val: val
        session: session
    ).done((result) ->
      console.log "git got: #{act} ->",result
      return
    ).fail((result) ->
      return
    ).always ->
      return


marginr=400
menu=20
resizer = ->
  w=$(window).width()
  h=$(window).height()
  #$("#rightcolumn").width(marginr)
  $("#rightcolumn").height(h-80)
  #$("#rightcolumn").css('height', h-50)


$ ->
  console.log "Script Starts..."
  #ajax()
  stream = new EventSource("/sse_demo.json")
  stream.addEventListener "message", (event) ->
    sse_data($.parseJSON(event.data))
    return
  $(window).resize ->
    resizer()
  resizer()




