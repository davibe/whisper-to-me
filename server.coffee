CoffeeScript    = require("coffee-script")
Express         = require("express")
File            = require("fs")
Path            = require("path")
Whisper         = require("./lib/whisper")
RequestContext  = require("./lib/request_context")


server = Express.createServer()
server.configure ->
  server.use Express.query()
  server.use Express.static("#{__dirname}/public")

  server.set "views", "#{__dirname}/public"
  server.set "view engine", "eco"
  server.set "view options", layout: "layout.eco"
  server.enable "json callback"

server.listen 8080

whisper = new Whisper(process.env.GRAPHITE_STORAGE || "/opt/graphite/storage")

# Main page lists all known metrics.
server.get "/", (req, res, next)->
  whisper.index (error, metrics)->
    return next(error) if error
    res.render "index", metrics: metrics

# Graph a particular target.
server.get "/graph/*", (req, res, next)->
  options =
    target: req.params[0]
    width: req.query.width || 800
    from: req.query.from
    to: req.query.until
    markers: req.query.markers

  res.render "graph", options
    

# This is supposed to work like Graphite's /render but only support JSON output.
server.get "/render", (req, res, next)->
  return if not req.query.target
  from = (Date.now() / 1000 - 1*60*60) # last 24 hours by default
  to = Date.now() / 1000
  width = req.query.width || 800

  if req.query.from
    from_value = parseInt req.query.from
    if from_value > 0
      from = from_value
    else
      from = to + from_value

  if req.query.until
    to_value = parseInt req.query.until
    if to_value > 0
      to = to_value
    else
      to = to + to_value

  console.log 'From ' + from
  console.log 'Until ' + to

  context = new RequestContext(whisper: whisper, from: from, to: to, width: width)
  context.evaluate req.query.target.split(";"), (error, results)->
    if error
      res.send error: error.message, 400
    else
      # filter out undefined values
      for k of results
        result = results[k]
        dp = []
        for k2 of result.datapoints
          point = result.datapoints[k2]
          if point[0] != undefined
            dp.push point
        result.datapoints = dp

      res.send results


# Serve require.js from Node module.
server.get "/javascripts/require.js", (req, res, next)->
  File.readFile "#{__dirname}/node_modules/requirejs/require.js", (error, script)->
    return next(error) if error
    res.send script, "Content-Type": "application/javascript"

# Serve D3 files from Node module.
server.get "/javascripts/d3*.js", (req, res, next)->
  name = req.params[0]
  File.readFile "#{__dirname}/node_modules/d3/d3#{name}.min.js", (error, script)->
    return next(error) if error
    res.send script, "Content-Type": "application/javascript"

# Serve CoffeeScript files, compiled on demand.
server.get "/javascripts/*.js", (req, res, next)->
  name = req.params[0]
  filename = "#{__dirname}/public/coffeescripts/#{name}.coffee"
  Path.exists filename, (exists)->
    if exists
      File.readFile filename, (error, script)->
        if error
          next error
        else
          res.send CoffeeScript.compile(script.toString("utf-8")), "Content-Type": "application/javascript"
    else
      next()

