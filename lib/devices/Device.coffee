# Properties and functionality as specified in [UPnP Device Architecture 1.0] [1].
#
# [1]: http://upnp.org/sdcps-and-certification/standards/device-architecture-documents/

"use strict"

async    = require 'async'
{exec}   = require 'child_process'
fs       = require 'fs'
http     = require 'http'
os       = require 'os'
makeUuid = require 'node-uuid'
xml      = require 'xml'

httpServer = require '../httpServer'
ssdp  = require '../ssdp'

DeviceControlProtocol = require '../DeviceControlProtocol'


class Device extends DeviceControlProtocol

    constructor: (@name, address) ->
        super
        @address = address if address?

    ssdp: { address: '239.255.255.250', port: 1900 }
    services: {}

    # Asynchronous operations to get and set some device properties.
    init: (cb) ->
        async.parallel
            address: (cb) => if @address? then cb null, @address else @getNetworkIP cb
            uuid:    (cb) => @getUuid cb
            port:    (cb) => httpServer.start.call @, cb
            (err, res) =>
                return @emit 'error', err if err?
                @uuid = "uuid:#{res.uuid}"
                @address = res.address
                @httpPort = res.port
                ssdp.start.call @
                @emit 'ready'


    # Generate HTTP header suiting the SSDP message type.
    makeSSDPMessage: (reqType, customHeaders) ->
        # These headers are included in all SSDP messages. Add them with `null` to
        # `customHeaders` object to get default values from `makeHeaders` function.
        for h in [ 'cache-control', 'server', 'usn', 'location' ]
            customHeaders[h] = null
        headers = @makeHeaders customHeaders

        # Build message string.
        message =
            if reqType is 'ok'
                [ "HTTP/1.1 200 OK" ]
            else
                [ "#{reqType.toUpperCase()} * HTTP/1.1" ]
        for header, value of headers
            message.push "#{header.toUpperCase()}: #{value}"

        # Add carriage returns and newlines as required by HTTP spec.
        message.push '\r\n'
        new Buffer message.join '\r\n'


    # Make `nt`'s for 3 messages about the device, and 1 for each service.
    makeNotificationTypes: ->
        [ 'upnp:rootdevice', @uuid, @makeType() ]
            .concat(@makeType.call service for name, service of @services)


    # Generate an HTTP header object for HTTP and SSDP messages.
    makeHeaders: (customHeaders) ->
        # Headers which always have the same values (if included).
        defaultHeaders =
            'cache-control': "max-age=1800"
            'content-type': 'text/xml; charset="utf-8"'
            ext: ''
            host: "#{@ssdp.address}:#{@ssdp.port}"
            location: @makeDescriptionUrl()
            server: [
                "#{os.type()}/#{os.release()}"
                "UPnP/#{@upnp.version}"
                "#{@name}/1.0" ].join ' '
            usn: @uuid +
                if @uuid is (customHeaders.nt or customHeaders.st) then ''
                else '::' + (customHeaders.nt or customHeaders.st)

        headers = {}
        for header of customHeaders
            headers[header.toUpperCase()] = customHeaders[header] or defaultHeaders[header.toLowerCase()]
        headers


    # Parse SSDP headers using the HTTP module parser.
    # The API is not documented and not guaranteed to be stable.
    parseRequest: (msg, rinfo, cb) ->
        parser = http.parsers.alloc()
        parser.reinitialize 'request'
        parser.onIncoming = (req) ->
            http.parsers.free parser
            cb null,
                method: req.method
                maxWait: req.headers.mx
                searchType: req.headers.st
                address: rinfo.address
                port: rinfo.port
        parser.execute msg, 0, msg.length


    # Attempt UUID persistance of devices across restarts.
    getUuid: (cb) ->
        uuidFile = "#{__dirname}/../../upnp-uuid"
        fs.readFile uuidFile, 'utf8', (err, file) =>
            data =  try
                        JSON.parse file
                    catch e
                        { }
            uuid = data[@type]?[@name]
            unless uuid?
                (data[@type]?={})[@name] = uuid = makeUuid()
                fs.writeFile uuidFile, JSON.stringify data
            # Always call back with UUID, existing or new.
            cb null, uuid


    # We need to get the server's internal network IP to send out in SSDP messages.
    # Only works on Linux and Mac.
    getNetworkIP: (cb) ->
        exec 'ifconfig', (err, stdout) ->
            switch process.platform
                when 'darwin'
                    filterRE = /\binet\s+([^\s]+)/g
                when 'linux'
                    filterRE = /\binet\b[^:]+:\s*([^\s]+)/g
                else
                    return cb new Error "Can't get IP address on this platform."
            isLocal = (address) -> /(127\.0\.0\.1|::1|fe80(:1)?::1(%.*)?)$/i.test address
            matches = stdout.match(filterRE) or ''
            ip = (match.replace(filterRE, '$1') for match in matches when !isLocal match)[0]
            err = if ip? then null else new Error "IP address could not be retrieved."
            cb err, ip


    # Build device description XML document.
    buildDescription: ->
        '<?xml version="1.0"?>' + xml [ { root: [
            { _attr: { xmlns: @makeNS() } }
            { specVersion: [ { major: @upnp.version.split('.')[0] }
                             { minor: @upnp.version.split('.')[1] } ] }
            { device: [
                { deviceType: @makeType() }
                { friendlyName: "#{@name} @ #{os.hostname()}".substr 0, 64 }
                { manufacturer: 'UPnP Device for Node.js' }
                { modelName: @name.substr 0, 32 }
                { UDN: @uuid }
                { serviceList:
                    { service: service.buildServiceElement() } for name, service of @services
                } ] }
        ] } ]


module.exports = Device
