getUrlVars = ->
  vars = {}
  hash = undefined
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
    @targets = {}
    @delegate = new DataSourceDelegate()
    @min = @max = @from = @to = null
    @palette = ["steelblue", "red", "green", "brown"]
    @interval = @options.interval || 1000
    @time_drift = 0

  setDelegate: (@delegate) =>

  getTargets: () =>
    result = []
    for key of @targets
      result.push @targets[key]
    return result

  start: =>
    @request()

  request: () =>
    start_time = Date.now()
    dReq = $.get "/render", @options
    dReq.fail @onRequestFailure
    dReq.done (results) =>
      now = Date.now()
      @elapsed = now - @last_update
      @last_update = Date.now()
      @onRequestDone(results)
      setTimeout @request, @interval

  onRequestDone: (results) =>
    @min = null
    @max = null
    @palette = ["steelblue", "red", "green", "violet"]
    for result in results
      target = result.target
      datapoints = []
      if result.datapoints.length == 0
        return
      # filter data points
      min = max = null
      for point in result.datapoints
        if point[0]
          p =
            y: point[0] # value
            x: point[1] # time
          if @min == null || p.y < @min
            @min = p.y
          if @max == null || p.y > @max
            @max = p.y
          if min == null || p.y < min
            min = p.y
          if max == null || p.y > max
            max = p.y
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
        color: @palette.shift()
        datapoints: datapoints
        lastupdate: datapoints[datapoints.length - 1].x

    @updateRange()
    @delegate.onUpdate this

  updateRange: () =>
    @from = @to = null
    for key of @targets
      datapoints = @targets[key].datapoints
      last = datapoints.length - 1
      min = datapoints[0].x
      max = datapoints[last].x
      if @from == null || min < @from
        @from = min
      if @to == null || max > @to
        @to = max
    if not @time_drift
      @time_drift = (Date.now()/1000) - @to


class DataView
  constructor: (@options) ->
    @el = $(@options.el).find 'svg'
    @palette = ["steelblue", "red", "green", "brown"]
    @source = new DataSource @options
    @source.setDelegate @
    @source.start()
    @first_cycle = true

  onUpdate: (source) =>
    #@clear()
    @render source

  clear: =>
    @el = $ @el
    content = @el.find '> *'
    content.remove()

  render: (source) =>
    # Create chart
    to = source.to
    from = source.from
    to = Date.now()
    # TODO this range is not always precise
    range = source.to - source.from
    from = (to - (range * 1000)) / 1000
    to /= 1000
    if not @min || source.min < @min
      @min = source.min
    min = @min
    if not @max || source.max > @max
      @max = source.max
    max = @max

    targets = source.getTargets()
    markers = @options.markers
    margin = 20
    y_fmt = d3.format(",.2f")

    chart = d3.select(@el.parent()[0]).select("svg")
    width = chart.attr("width") - margin * 5
    height = chart.attr("height") - margin * (3 + targets.length) * 1.2

    vis = chart.selectAll ("g")
    if not vis[0][0]
      vis = chart.append("svg:g")
        .attr("transform", "translate(#{margin * 3},#{margin})")

    x_scale = d3.scale.linear().domain([to, from]).range([width, 0])
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
    factor = (@source.elapsed * 0.8) / (to - from)
    animate = (selector, refresh) =>
      selector.attr('transform', null)
      refresh(selector)
      selector
        .transition()
        .ease('linear')
        .duration(@source.elapsed)
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
        .style("stroke-width", 0.5)
        .style("stroke", '#efefef')

    line_y = vis.selectAll("line.y")
    animate line_y, (selector) ->
      selector
        .data(y_scale.ticks(height / 50))
        .enter()
        .append("svg:line")
        .attr("x1", 0)
        .attr("x2", width + 1)
        .attr("y1", y_scale)
        .attr("y2", y_scale)
        .attr("class", (d, i)-> if i > 0 then "y" else "y axis" )
        .style("stroke-width", 0.5)
        .style("stroke", '#efefef')

    # Add labels at bottom of chart
    if @first_cycle
      labels = vis.append("svg:svg")
      labels
        .attr("class", "stats_label")
        .attr("x", 0)
        .attr("y", height + margin * 2)
        .attr("width", width - 400)
        .attr("height", margin * targets.length * 1.2)
      labels
        .selectAll("text.label")
        .data(targets)
        .enter()
        .append("svg:text")
        .attr("x", 0)
        .attr("y", (d, i)-> margin + margin * i * 1.2 )
        .attr("class", "label")
        .style("stroke", (d)-> d.color)
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
      .style("stroke", (d)-> d.color).attr("text-anchor", "end")
      .style("stroke-width", 0.25)


    # Draw each line
    i = 0
    for target in targets
      target.color = @palette[i]
      i++
      svg_line = d3.svg.line().interpolate("basis")
        .x( (d)-> x_scale(d.x) )
        .y( (d)-> y_scale(d.y) )

      line = vis.selectAll(".line")
      if @first_cycle
        line
          .data([target.datapoints])
          .enter().append("svg:path")
          .attr("class", "line")
          .attr("d", svg_line)
          .style("stroke-width", target.width * 2)
          .style("stroke", target.color)

      line = vis.selectAll(".line")
      animate line, (selector) =>
        selector
          .data([target.datapoints])
          .attr("d", svg_line)

      # fill area under graph
      svg_area = d3.svg.area().interpolate('basis')
        .x((d) -> x_scale d.x)
        .y((d) -> y_scale 0)
        .y1((d) -> y_scale d.y)

      area = vis.selectAll(".area")
      if @first_cycle
        area
          .data([target.datapoints])
          .enter()
          .append("svg:path")
          .attr("class", "area")
          .on("click", @source.request)
          .attr("d", svg_area)
          .style("fill", target.color)
          .style("opacity", 0.15)

      area = vis.selectAll(".area")
      animate area, (selector) ->
        selector
          .data([target.datapoints])
          .attr("d", svg_area)

      # add markers
      if markers
        markers = vis.selectAll(".circles")
        if @first_cycle
          markers.data(target.datapoints)
            .enter().append("svg:circle")
            .attr("class", "circles")
            .attr("r", 2.5)
            .attr("cx", (d) -> x_scale d.x)
            .attr("cy", (d) -> y_scale d.y)
            .style("stroke", target.color)
            .style("stroke-width", 1)
            .style('fill', '#fff')

        markers = vis.selectAll(".circles")
        animate markers, (selector) =>
          selector
            .attr("transform", "translate(" + (+0) + ")")
            .data(target.datapoints)
            .attr("r", 2.5)
            .attr("cx", (d) -> x_scale d.x)
            .attr("cy", (d) -> y_scale d.y)

    # Draw Y (value) scale
    if @first_cycle
      # left clipping
      # TODO use path instead of thick line
      vis
        .append("svg:line")
        .attr("x1", -30)
        .attr("x2", -30)
        .attr("y1", height+40)
        .attr("y2", -10)
        .style("stroke-width", 80)
        .style("stroke", '#fff')
      # right clipping
      vis
        .append("svg:line")
        .attr("x1", width-30)
        .attr("x2", width-30)
        .attr("y1", height+40)
        .attr("y2", -10)
        .style("stroke-width", 80)
        .style("stroke", '#fff')

      test = vis.append("svg:line")
        .attr("x", 100)
        .attr("y", 100)
        .attr("dx", x_scale 1000)
        .attr("dy", x_scale 1000)
        .style("stroke-width", 1.5)
        .style("stroke", '#000')

      text_y = vis.selectAll("text.y")
      text_y
        .data(y_scale.ticks(height / 50))
        .enter()
        .append("svg:text")
        .attr("x", -10)
        .attr("y", y_scale)
        .attr("dy", 3)
        .attr("dx", -10)
        .attr("class", "y")
        .attr("text-anchor", "end")
        .text(y_fmt)

    @first_cycle = false


define [], ->
  return (el, target)->
    $el = $(el)
    target = target || $el.data("target")
    width = $el.data("width")
    from = $el.data("from")
    to = $el.data("until")
    markers = $el.data("markers") == true

    options =
      target: target
      width: width
      from: from
      to: to
      markers: markers
      el: el

    test = new DataView options
    return
