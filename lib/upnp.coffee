# UPnP device creation.

"use strict"

{EventEmitter} = require 'events'

# Require all currently implemented devices.
#
# * [`MediaServer`](MediaServer.html)
devices = 
    mediaserver: require './devices/MediaServer'
    binarylight: require './devices/BinaryLight'

# Returns a device which will emit the `ready` event when asynchronous
# initialization operations finishes.
exports.createDevice = (deviceType, name, address) ->
  type = deviceType.toLowerCase()
  unless type of devices
    device = new EventEmitter
    device.emit 'error',
      new Error "UPnP device of type #{deviceType} is not yet implemented."
    return device

  new devices[type] name, address
