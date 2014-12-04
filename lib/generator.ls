Promise = require \bluebird
cheerio = require \cheerio
_ = require \lodash-node
path = require \path
dblite = require \dblite

{promisify, promisifyAll} = Promise
pmkdirp = promisify require \mkdirp
prequest = promisify require \request
pfs = promisifyAll require \fs
prmdir = promisify require \rimraf

module.exports =
	generate: (root = "#{__dirname}/../plantuml.docset")->
		prmdir root
		.then ->
			getPage ""
		.then ($)->
			hrefs = ($ '#menu .drop')map ->
				($ @)attr \href
			.toArray!

			Promise.all hrefs.map (href)->
#			Promise.all hrefs.slice(0, 2).map (href)->
				getPage href
				.then ($)->
					$content = $ '#content'
					$content.find( 'div,script').remove!

					name = $content.find 'h1' .text!

					images = $content.find 'img' .map ->
						($ @)attr \src
					.toArray!

					indexes = $content.find 'h2' .map ->
						$h2 = $ @

						section = $h2.text!
						$h2.before "<a name=\"//apple_ref/cpp/Guide/#{section}\" class=\"dashAnchor\"></a>"

						{
							name: (name.replace /\s+Diagram/i, '') + ' - ' + section
							type: 'Guide'
							path: "#{href}##{$h2.attr 'id'}"
						}
					.toArray!

					{
						name
						html: $content.html!
						images
						indexes
						href
					}
		.then (pages)->
			htmlRoot = "#{root}/Contents/Resources/Documents"
			dbPath = "#{root}/Contents/Resources/docSet.dsidx"

			pmkdirp htmlRoot
			.then ~>
				pfs.writeFileAsync dbPath, ''
			.then ~>
				pfs.readFileAsync __dirname + '/../assets/icon.png'
			.then (icon)~>
				pfs.writeFileAsync "#{root}/icon.png", icon
			.then ~>
				pfs.writeFileAsync (path.join htmlRoot, 'index.html'), template {
					name: 'PlantUML'
					html: '<ul>' + (pages.map mapper .join '') + '</ul>'
				}

				function mapper page
					"""
					<li><a href="#{page.href}">#{page.name}</a></li>
					"""

			.then ~>
				db <~ Promise.using open dbPath

				<~ db.queryAsync "CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);" .then
				<~ db.queryAsync "CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);" .then

				Promise.all pages.map (page)->

					target = path.join htmlRoot, page.href

					<~ pmkdirp (path.dirname target) .then

					result = [
						pfs.writeFileAsync target, template page
					];

					result.concat page.images.map (src)->
						download src
						.then (body)->
							target = path.join htmlRoot, src
							<~ pmkdirp (path.dirname target) .then
							pfs.writeFileAsync target, body

					result.push db.query "INSERT INTO searchIndex(name, type, path) VALUES ('#{page.name}', 'Diagram', '#{page.href}');"

					result.concat page.indexes.map ->
						db.query "INSERT INTO searchIndex(name, type, path) VALUES ('#{it.name}', '#{it.type}', '#{it.path}');"

					result
		.then ->
			pfs.writeFileAsync "#{root}/Contents/Info.plist", plistContent

function download uri
	console.log "download #{uri}"
	prequest do
		url: "http://www.plantuml.com/#{uri}"
		encoding: null
	.spread (res)->
		res.body

function getPage uri
	console.log "get /#{uri}"
	prequest do
		url: "http://www.plantuml.com/#{uri}"
	.spread (res)->
		cheerio.load res.body

function open dbPath
	db = dblite dbPath

	Promise.cast promisifyAll db
	.disposer ->
		console.log "dispose"
		db.close!

template = _.template """
<!DOCTYPE html>
<html>
<head>
	<meta charset="UTF-8">
	<title><%=name%></title>
</head>
<body>
<%=html%>
"""

plistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>plantuml</string>
	<key>CFBundleName</key>
	<string>PlantUML</string>
	<key>DocSetPlatformFamily</key>
	<string>plantuml</string>
	<key>isDashDocset</key>
	<true/>
	<key>DashDocSetFamily</key>
	<string>dashtoc</string>
	<key>dashIndexFilePath</key>
	<string>index.html</string>
</dict>
</plist>
"""