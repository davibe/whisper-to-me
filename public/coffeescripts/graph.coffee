getUrlVars = ->
  vars = {}
  hash = undefined
  if window.location.href.indexOf("?") == -1
    return false
  hashes = window.location.href.slice(window.location.href.indexOf("?") + 1).split("&")
  i = 0
  while i < hashes.length
    hash = hashes[i].split("=")
    vars[hash[0]] = hash[1]
    i++
  return vars

# Restore values from url params
$(document).ready () ->
  form = $ 'form'
  form.change ()->
    form.submit()
  values = getUrlVars()
  for key of values
    element = form.find '[name='+key+']'
    if element.attr('type') == 'checkbox'
      element.attr 'checked', 'checked'
      continue

    element.val values[key]

class DataSourceDelegate
  onUpdate: (targets) ->
    throw 'Not Implemented'

class DataSource
  constructor: (@options) ->
    # Colors user for graph targets
    @url = @options.url
    @targets = {}
    @interval = @options.interval || 1000
    @min = @max = @from = @to = null
    @time_drift = 0
    @stopped = true
    @delegate = new DataSourceDelegate()

  setDelegate: (@delegate) =>

  getTargets: () =>
    # Returns a list of targets
    result = []
    for key of @targets
      result.push @targets[key]
    return result

  start: =>
    @stopped = false
    @request()

  stop: =>
    @stopped = true

  request: () =>
    @options.width = (Math.abs @options.from) + 2
    if @options.width > 300
      @options.width = 300
    dReq = $.get @url, @options
    dReq.fail @onRequestFailure
    dReq.done (results) =>
      @onRequestDone(results)
      if not @stopped
        setTimeout @request, @interval

  onRequestDone: (results) =>
    @min = @max = @from = @to = null

    for result in results
      target = result.target
      datapoints = []
      if result.datapoints.length == 0 then return

      min = max = null # of the target
      for point in result.datapoints
        if point[0]
          p =
            y: point[0] # value
            x: point[1] # time
          if @min == null || p.y < @min then @min = p.y
          if @max == null || p.y > @max then @max = p.y
          if min == null || p.y < min then min = p.y
          if max == null || p.y > max then max = p.y
          datapoints.push p

      label = target.split '.'
      label.shift()
      label = label.join ' > '
      @targets[target] =
        target: target
        label: label
        last: datapoints[datapoints.length-1].y
        min: min
        max: max
        datapoints: datapoints
        lastupdate: datapoints[datapoints.length - 1].x

      # adjust from and to
      last = datapoints.length - 1
      min = datapoints[0].x
      max = datapoints[last].x
      if @from == null || min < @from then @from = min
      if @to == null || max > @to then @to = max

    if not @time_drift then @time_drift = (Date.now()/1000) - @to
    @delegate.onUpdate this

  onRequestFailure: (results) =>
    if window.console and window.console.log
      console.log 'DataSource: Request failed'


class DataView
  constructor: (@options) ->
    @palette = ["steelblue", "red", "green", "brown"]
    @el = $(@options.el).find 'svg'
    vars = getUrlVars()
    if not vars
      vars =
        from : "-60"
        interval: "1000"

    for key of vars
      @options[key] = vars[key]
    @options.from = parseInt @options.from
    @options.width = parseInt @options.width if @options.width
    @source = new DataSource @options
    @source.setDelegate @
    @source.start()
    @first_cycle = true

  onUpdate: (source) =>
    @render source

  render: (source) =>
    # Create chart
    to = (Date.now()/1000) - source.time_drift
    if @previousTo
      elapsed = (to - @previousTo) * 1000
    else
      elapsed = source.interval
    @previousTo = to
    from = to + @source.options.from
    range = source.to - from
    if not @min || source.min < @min
      @min = source.min
    min = @min
    if not @max || source.max > @max
      @max = source.max
    max = @max
    min = source.min
    max = source.max
    min -= (max-min)/1000

    chart = d3.select(@el.parent()[0]).select("svg")
    chart_width = chart.attr("width")
    targets = source.getTargets()
    markers = @options.markers
    margin = if chart_width < 501 then 15 else 20
    y_fmt = d3.format(",.2f")

    chart = d3.select(@el.parent()[0]).select("svg")
    width = chart.attr("width") - margin * 4
    height = chart.attr("height") - margin * (3 + targets.length) * 1.2

    vis = chart.selectAll ("g")
    if not vis[0][0]
      vis = chart.append("svg:g")
        .attr("transform", "translate(#{margin * 3},#{margin})")

    time_to_px = (time) ->
      return time * width / range

    x_scale = d3.scale.linear().domain([to, from]).range([width + (time_to_px elapsed/1000), 0])
    y_scale = d3.scale.linear().domain([min, max]).range([height, 0])
      .nice().clamp(true)

    # Format time based on resolution
    range = to - from
    if range < 120
      fmt_time = d3.time.format("%H:%M:%S")
    else if range < 86400
      fmt_time = d3.time.format("%H:%M")
    else if range < 604800
      fmt_time = d3.time.format("%a %H:%M")
    else
      fmt_time = d3.time.format("%a %e")

    # animate x translation
    factor = time_to_px elapsed/1000#(elapsed * 0.8) / (to - from)

    animate = (selector, refresh) =>
      if not @options.animated
        refresh(selector)
        return
      selector.attr('transform', "")
      refresh(selector)
      selector
        .transition()
        .ease('linear')
        .duration(elapsed)
        .attr("transform", "translate(" + (-1 * factor) + ")")

    # Draw X (time) scale
    if @first_cycle
      text_x = vis.selectAll("text.x")
      text_x
        .data(x_scale.ticks(width / 100))
        .enter().append("svg:text")
        .attr("x", x_scale)
        .attr("y", height + margin)
        .attr("dy", margin - 14)
        .attr("text-anchor", "middle")
        .attr("class", "x")
        .text( (d)-> fmt_time(new Date(d * 1000)) )

    # Refresh and animate x time scale
    text_x = vis.selectAll("text.x")
    animate text_x, (selector)->
      selector
        .data(x_scale.ticks(width / 100))
        .attr("x", x_scale)
        .attr("y", height + margin)
        .attr("dy", margin - 14)
        .attr("text-anchor", "middle")
        .attr("class", "x")
        .text( (d)-> fmt_time(new Date(d * 1000)) )
        .exit().remove()

    if @first_cycle
      line_x = vis.selectAll("line.x")
      line_x
        .data(x_scale.ticks(width / 10))
        .enter()
        .append("svg:line")
        .attr("x1", (d)-> x_scale(d) )
        .attr("x2", (d)-> x_scale(d) )
        .attr("y1", height)
        .attr("y2", 0)
        .attr("class", "x")
        .style("stroke-width", 0.5)
        .style("stroke", '#efefef')
        .attr("class", (d, i)-> if i > 0 then "x" else "x axis" )


    line_x = vis.selectAll("line.x")
    animate line_x, (selector) ->
      selector
        .data(x_scale.ticks(width / 10))
        .attr("x1", (d)-> x_scale(d) )
        .attr("x2", (d)-> x_scale(d) )
        .attr("y1", height)
        .attr("y2", 0)
        .attr("class", "x")
        .style("stroke-width", 0.5)
        .style("stroke", '#efefef')
        .attr("class", (d, i)-> if i > 0 then "x" else "x axis" )
        .exit().remove()

    if @first_cycle
      line_y = vis.selectAll("line.y")
      line_y
        .data(y_scale.ticks(height / 50))
        .enter()
        .append("svg:line")
        .attr("x1", 0)
        .attr("x2", width + 1)
        .attr("y1", y_scale)
        .attr("y2", y_scale)
        .attr("class", (d, i)-> if i > 0 then "y" else "y axis" )
        .style("stroke-width", 0.16)
        .style("stroke", '#000')


    vis.selectAll("line.y").remove()
    line_y = vis.selectAll("line.y")
    line_y
        .data(y_scale.ticks(height / 50))
        .enter()
        .append("svg:line")
        .attr("x1", 10)
        .attr("x2", width + 1)
        .attr("y1", y_scale)
        .attr("y2", y_scale)
        .attr("class", (d, i)-> if i > 0 then "y" else "y axis")
        .attr("opacity", 0.1)
        .style("stroke-width", 0.16)
        .style("stroke", '#000')

    # Add labels at bottom of chart
    if @first_cycle
      labels = vis.append("svg:svg")
      labels
        .attr("x", 0)
        .attr("y", height + margin * 2)
        .attr("width", width)
        .attr("height", margin * targets.length * 1.2)
      labels
        .selectAll("text.label")
        .data(targets)
        .enter()
        .append("svg:text")
        .attr("x", 0)
        .attr("y", (d, i)-> margin + margin * i * 1.2 )
        .attr("class", "label")
        .style("stroke", (d, i)=> @palette[i])
        .style("stroke-width", 0.25)
        .text( (d)-> d.label )

    if @first_cycle
      ranges = vis.append("svg:svg")
      ranges
        .attr("class", "stats_range")
        .attr("x", width - 400)
        .attr("y", height + margin * 2)
        .attr("width", 400)
        .attr("height", margin * targets.length * 1.2)
    else
      ranges = vis.select(".stats_range")

    labels = ranges.selectAll(".label")
    labels.remove()
    labels = ranges.selectAll(".label")
    labels
      .data(targets)
      .enter()
      .append("svg:text")
      .text( (d)-> if d.last then "Min #{y_fmt(d.min)}  Max #{y_fmt(d.max)}  Last #{y_fmt(d.last)}" else "" )
      .attr("class", "label")
      .attr("x", 400)
      .attr("y", (d, i)-> margin + margin * i * 1.2 )
      .style("stroke", (d, i)=> @palette[i]).attr("text-anchor", "end")
      .style("stroke-width", 0.25)


    # Draw each line
    i = 0
    for target in targets
      target.color = @palette[i]
      i++
      svg_line = d3.svg.line().interpolate("basis")
        .x( (d)-> x_scale(d.x) )
        .y( (d)-> y_scale(d.y) )

      line = vis.selectAll(".line"+i)
      if @first_cycle
        line
          .data([target.datapoints])
          .enter().append("svg:path")
          .attr("class", "line"+i)
          .attr("d", svg_line)
          .style("stroke-width", target.width * 2)
          .style("stroke", target.color)

      line = vis.selectAll(".line"+i)
      animate line, (selector) =>
        selector
          .data([target.datapoints])
          .attr("d", svg_line)

      # fill area under graph
      if @options.area
        svg_area = d3.svg.area().interpolate('basis')
          .x((d) -> x_scale d.x)
          .y((d) -> y_scale 0)
          .y1((d) -> y_scale d.y)

        area = vis.selectAll(".area"+i)
        if @first_cycle
          area
            .data([target.datapoints])
            .enter()
            .append("svg:path")
            .attr("class", "area"+i)
            .on("click", @source.request)
            .attr("d", svg_area)
            .style("fill", target.color)
            .style("opacity", 0.15)

        area = vis.selectAll(".area"+i)
        animate area, (selector) ->
          selector
            .data([target.datapoints])
            .attr("d", svg_area)

      # add markers
      if markers
        markers = vis.selectAll(".circles"+i)
        if @first_cycle
          markers.data(target.datapoints)
            .enter().append("svg:circle")
            .attr("class", "circles"+i)
            .attr("r", 2.5)
            .attr("cx", (d) -> x_scale d.x)
            .attr("cy", (d) -> y_scale d.y)
            .style("stroke", target.color)
            .style("stroke-width", 1)
            .style('fill', '#fff')

        markers = vis.selectAll(".circles"+i)
        animate markers, (selector) =>
          selector
            .attr("transform", "translate(" + (+0) + ")")
            .data(target.datapoints)
            .attr("cx", (d) -> x_scale d.x)
            .attr("cy", (d) -> y_scale d.y)

    # left clipping
    svg_area = d3.svg.area().interpolate('linear')
      .x((d) -> d.x)
      .y((d) -> 0)
      .y1((d) -> d.y)

    vis.selectAll(".leftclip").remove()
    vis.selectAll(".leftclip")
      .data([
        [
          {x: -100, y: -100},
          {x: -100, y: height+30},
          {x: 10, y: height+30},
          {x: 10, y: 0}
        ]
      ])
      .enter()
      .append("svg:path")
      .attr("d", svg_area)
      .attr("class", "leftclip")
      .style("fill", "#fff")

    # right clipping
    vis.selectAll(".rightclip").remove()
    vis.selectAll(".rightclip")
      .data([
        [
          {x: chart_width-100, y: -100},
          {x: chart_width-100, y: height+30},
          {x: width+100, y: height+30},
          {x: width+100, y: -100}
        ]
      ])
      .enter()
      .append("svg:path")
      .attr("d", svg_area)
      .attr("opacity", 1)
      .attr("class", "rightclip")
      .style("fill", "#fff")

    # y-axis values
    vis.selectAll("text.y").remove()
    vis.selectAll("text.y")
      .data(y_scale.ticks(height / 50))
      .enter()
      .append("svg:text")
      .attr("x", 0)
      .attr("y", y_scale)
      .attr("dy", 3)
      .attr("dx", -10)
      .attr("class", "y")
      .attr("text-anchor", "end")
      .text(y_fmt)

    if (chart_width > 700)
      vis.selectAll("text")
          .attr("font-size", 16)
      @first_cycle = false

    else if (chart_width > 500)
      vis.selectAll("text")
          .attr("font-size", 14)
      @first_cycle = false

    else if (chart_width > 400)
      vis.selectAll("text")
          .attr("font-size", 12)
      @first_cycle = false

    else if (chart_width > 100)
      vis.selectAll("text")
          .attr("font-size", 10)
      @first_cycle = false

define [], ->
  return (options)->
    options.url = options.url || "/render"
    new DataView options
    return
