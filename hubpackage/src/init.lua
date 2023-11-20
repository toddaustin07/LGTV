--[[
  Copyright 2023 Todd Austin

  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
  except in compliance with the License. You may obtain a copy of the License at:

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the
  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
  either express or implied. See the License for the specific language governing permissions
  and limitations under the License.


  DESCRIPTION
  
  LG TV Driver

  Reference:  https://github.com/klattimer/LGWebOSRemote/tree/master/LGTV

--]]

-- Edge libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local cosock = require "cosock"
local socket = require "cosock.socket"                                  -- for time only
local log = require "log"
local utils = require "st.utils"

-- Driver modules
local ws = require 'websocket'
local discovery = require "discovery"
local semaphore = require "semaphore"
local authdata = require "authreq"
local cx = require "common"
local wol = require "wakeonlan"

newly_added = {}
found_hubs = {}
local applists = {}

-- Device Capabilities

cap_lgmsg = capabilities["partyvoice23922.lgmessage"]
cap_lginput = capabilities["partyvoice23922.lgmediainputsource"]
cap_status = capabilities["partyvoice23922.status"]

-- Global variables
thisDriver = {}
hubs_auto_discovered = 0
disco_sem = {}

-- Module variables
local initialized = false
local devices_inited = 0

-- WebSocket OpCodes
local CONTINUE_FRAME = 0
local TEXT_FRAME = 1
local BINARY_FRAME = 2
local CONNECTED_CLOSE_FRAME = 8
local PING_FRAME = 9
local PONG_FRAME = 10

-- WebSocket Constants
local SSL_PARMS = {
                    mode = "client",
                    protocol = "any",
                    verify = "none",
                    options = "all"
                  }

-- CONSTANTS
local WSSPORT = 3001

local MAXCMDIDS = 99
local MAX_CMD_AGE = 30000    -- (milliseconds) if sent cmds old, they'll be deleted (assume they were ignored by hub)

local POSTCMD_REFRESH_DELAY = 5   -- number of seconds to wait before issuing refresh after a command

DEVICE_PROFILE = 'lgtv.v1'

------------------------------------------------------------------------


function send_command(device, msgdata)
  
  local client = device:get_field('ws_client')
  if client then
  
    local ok, close_was_clean, close_code, close_reason = client:send(msgdata)

    if not ok then
      log.error ('Websocket Send failed:')
      log.error (close_was_clean, close_code, close_reason)
    else
      log.info ('Message sent')
    end

  else
    log.warn ('Cannot send message; not connected', msgdata)
  end

end


local wsmsgid = 0

local function gen_msgid(prefix)

  wsmsgid = wsmsgid + 1
  
  if wsmsgid > 999 then; wsmsgid = 1; end

  if prefix then
    return prefix .. '_' .. tostring(wsmsgid)
  else
    return tostring(wsmsgid)
  end
  
end

local function build_messsage(msgtype, uri, payload, prefix)

  local msgobj = {}
  
  msgobj.type = msgtype
  msgobj.id = gen_msgid(prefix)
  msgobj.uri = uri
  if payload then
    msgobj.payload = payload
  end
  
  return cx.encode_json(msgobj)

end

local function update_device(device)

  send_command(device, build_messsage("request", "ssap://com.webos.service.tvpower/power/getPowerState"))
  
  socket.sleep(.5)
  
  send_command(device, build_messsage("request", "ssap://audio/getStatus"))
  
  socket.sleep(.5)
  
  send_command(device, build_messsage("request", "ssap://tv/getCurrentChannel"))

end

local function reset_refresh_timer(device)

  if device:get_field('refresh_timer') then; thisDriver:cancel_timer(device:get_field('refresh_timer')); end
  
  local timer = thisDriver:call_on_schedule(device.preferences.freq, function()
      update_device(device)
    end)
    
  device:set_field('refresh_timer', timer)

end


local function init_device(device)

  update_device(device)
   
  socket.sleep(.5)
  
  send_command(device, build_messsage("request", "ssap://com.webos.applicationManager/listApps"))
  
  reset_refresh_timer(device)

end


local function parse_response(device, payload)


  for key, value in pairs(payload) do
  
    if key == 'state' then
      if value == 'Active' then
        device:emit_event(capabilities.switch.switch('on'))
      else
        device:emit_event(capabilities.switch.switch('off'))
      end
      
    elseif key == 'volume' then
      device:emit_event(capabilities.audioVolume.volume(tonumber(value)))
      
    elseif key == 'mute' then
      local mutestate = {['true'] = 'muted', ['false'] = 'unmuted'}
      device:emit_event(capabilities.audioMute.mute(mutestate[tostring(value)]))
      
    elseif key == 'apps' then
    
      local applist = {}
      for _, app in ipairs(value) do
        table.insert(applist, { id = app.id, name = app.title })
      end
      device:emit_event(capabilities.mediaPresets.presets(applist))
        
    end
  end

end


local function handle_response_frame(device, payload)

  local response_table = cx.decode_json(payload)
  if response_table == nil then; return; end
  
  --cx.disptable(response_table, '  ', 3)
  
  if response_table.type == 'response' then
    if response_table.id == 'register_0' then
      if response_table.payload.pairingType == 'PROMPT' then
        log.info('Pairing...')
        device:emit_event(cap_status.status('Pairing'))
      else
        log.warn('Unexpected pairing type', response_table.payload.pairintType)
        device:emit_event(cap_status.status(response_table.payload.pairingType))
      end
    else
      log.info(string.format('Response message to be handled id=%s:', response_table.id))
      if response_table.payload then
        if not response_table.payload.apps then
          cx.disptable(response_table.payload, '  ', 4)
        end
        
        print ("returnValue:", response_table.payload.returnValue, type(response_table.payload.returnValue))
        if response_table.payload.returnValue == true then
          parse_response(device, response_table.payload)
        else
          log.error('Unexpected returnValue', response_table.payload.returnValue)
        end
      else
        log.warn('Empty payload - no action taken')
      end
    end
  
  elseif response_table.type == 'registered' then
    log.info ('Successfully registered with LG webOS; key=', response_table.payload['client-key'])
    device:set_field('lg_registration_key', response_table.payload['client-key'], { ['persist'] = true })
    device:emit_event(cap_status.status('Registered'))
    init_device(device)
  
  elseif response_table.type == 'error' then
    log.error(string.format('Error reported in response: %s - %s', response_table.error, response_table.payload.errorText))
  
  else
    log.warn(string.format('Unexpected message type: %s; with following payload:', response_table.type))
    if response_table.payload then
      cx.disptable(response_table.payload, '  ', 4)
    end
  end
  
end


local function handshake_lgtv(device)

  local handshake = authdata

  if device:get_field('lg_registration_key') then
    log.info('Handshake')
    handshake.payload['client-key'] = device:get_field('lg_registration_key')
  end
  
  send_command(device, cx.encode_json(handshake))

end


local function pingmonitor()

  log.debug('Checking last pings...')

  local devicelist = thisDriver:get_devices()
  
  for _, device in ipairs(devicelist) do
  
    if device:get_field('ws_client') then
    
      local time_since_last_ping = socket.gettime() - device:get_field('lastping')
    
      if (time_since_last_ping) > 60 then
      
        log.warn(string.format('%s has not pinged in %s seconds', device.label, time_since_last_ping))
        
        device:offline()
        device:set_field('ws_client', nil)
        local sock = device:get_field('ws_sock')
        device:set_field('ws_sock', nil)
        thisDriver:unregister_channel_handler(sock)
        
        device.thread:queue_event(init_connection, device)
        
      end
    end
  end

end


-- Initialize hub connection
function init_connection(device)

  local wssaddr = device:get_field('WSSaddr')
  log.debug ('Retrieved device address:', wssaddr)

  --local uri = 'wss://' .. wssaddr
  local uri = 'ws://' .. wssaddr
  
  log.info (string.format('Initializing %s at %s', device.label, uri))

  local client = ws.client.sync({timeout=2})
          
  if not client then
    log.error ('Failed to create websocket client')
    return
  end
  
  --local ok, code, headers, sock = client:connect(uri,'echo', SSL_PARMS)
  local ok, code, headers, sock = client:connect(uri,'echo')
  
  log.info (string.format('%s: WS Connect returned: ok=%s, code=%s, headers=%s', device.label, ok, code, headers))
  
  if not ok then
    log.error ('Could not connect:', code)
    log.info(string.format('%s: WS Connect will retry in 15 seconds', device.label))
    device:emit_event(cap_status.status('Connect retry (' .. wssaddr .. ')'))
    device:offline()
    local retrytimer = thisDriver:call_with_delay(15, function()
        init_connection(device)
      end)
    device:set_field('retrytimer', retrytimer)
    return
  end
  
  -- Get here if connected successfully
  device:online()
  device:emit_event(cap_status.status('Connected'))
  
  device:set_field('retrytimer', nil)
  device:set_field('ws_client', client)
  device:set_field('ws_sock', sock)

  thisDriver:register_channel_handler(sock, function ()
      local payload, opcode, c, d, err = client:receive()
      
      log.debug (string.format('Received opcode=%s, c=%s, d=%s, err=%s', opcode, c, d, err))
      
      if opcode ~= PING_FRAME then
        
        if opcode == TEXT_FRAME then
          log.debug ('WS Receive TEXT frame payload')
          log.debug (payload)
          handle_response_frame(device, payload)
          
        elseif opcode == CONNECTED_CLOSE_FRAME then
          log.warn ('Connection has been closed by request')
          device:emit_event(cap_status.status('Connection closed'))
          thisDriver:unregister_channel_handler(sock)
          sock:close()
          return
        end
        
      else
        client:send(payload, PONG_FRAME)
        device:set_field('lastping', socket.gettime())
      end
      
      if err then
      
        if err == 'closed' then
          log.warn ('Connection has been closed')
        else
          log.error ('Receive error:', err)
        end
        
        device:set_field('ws_client', nil)
        device:set_field('ws_sock', nil)
        thisDriver:unregister_channel_handler(sock)
        device:emit_event(cap_status.status('Connect retry...'))
        device:offline()
        log.info(string.format('%s: WS Re-Connect attempt in 15 seconds', device.label))
        local retrytimer = thisDriver:call_with_delay(15, function()
            init_connection(device)
          end)
        device:set_field('retrytimer', retrytimer)
        return
        
      end
    end)
 
  handshake_lgtv(device)
  
end


local function shutdown_device(driver, device, msg)

  if device:get_field('retrytimer') then
    thisDriver:cancel_timer(device:get_field('retrytimer'))
  end
  
  if device:get_field('refresh_timer') then
    thisDriver:cancel_timer(device:get_field('refresh_timer'))
  end

  local client = device:get_field('ws_client')
  if client then
    local was_clean,code,reason = client:close(1000, msg)
    log.debug('Client close result:', was_clean, code, reason)
  end
  
  device:set_field('ws_client', nil)
  device:set_field('ws_sock', nil)

end


------------------------------------------------------------------------
--                    CAPABILITY HANDLERS
------------------------------------------------------------------------


local function handle_refresh(driver, device, command)
  -- note: refreshes can be Edge-induced or user-induced
  log.info (string.format('>>> Refresh requested for %s<<<', device.label))
  
 
  -- Inhibit refreshes during device creation
  local gorefresh = true
  if device:get_field('createtime') then
    local now = socket.gettime()
    local diff = now - device:get_field('createtime')
    log.debug ('Time since creation', diff)
    if diff < 5 then
      gorefresh = false
    end
  end
  
  if gorefresh then
  
    if not device:get_field('ws_client') then
      if device:get_field('retrytimer') then
        driver:cancel_timer(device:get_field('retrytimer'))
      end
      
      device.thread:queue_event(init_connection, device)
      
    else
      init_device(device)
    end
      
    device:set_field('lastrefresh', socket.gettime())
    
  else
    log.info ('>>>> Refresh ignored')
  end
end


local function handle_switch(driver, device, command)

  log.debug ('Switch changed to', command.command)
  device:emit_event(capabilities.switch.switch(command.command))
  
  if command.command == 'on' then
     wol.do_wakeonlan(device.preferences.macaddr, device.preferences.bcastaddr)
  else
    send_command(device, build_messsage("request", "ssap://system/turnOff"))
  end
  
end


local function handle_volume(_, device, command)

  log.debug("Volume set to " .. command.args.volume)
  
  device:emit_event(capabilities.audioVolume.volume(command.args.volume))
  
  send_command(device, build_messsage("request", "ssap://audio/setVolume", {volume=command.args.volume}))
  
end


local function handle_mute(_, device, command)

  log.debug("Mute set to " .. command.command, command.args.state)
  
  local newstate
  
  if command.command == 'setMute' then
    newstate = command.args.state
  else
    newstate = command.command .. 'd'
  end
  
  device:emit_event(capabilities.audioMute.mute(newstate))
  
  local lgmute = { muted = true, unmuted = false }
  
  send_command(device, build_messsage("request", "ssap://audio/setMute", {mute=lgmute[newstate]}))

end

local function handle_app(driver, device, command)
  
  log.info ('Media Preset action:', command.command, command.args.presetId)

  send_command(device, build_messsage("request", "ssap://system.launcher/launch", {id=command.args.presetId}))
  
end

local function handle_channel(_, device, command)

  log.debug("Channel set to " .. command.command, command.args.tvChannel)
  
  device:emit_event(capabilities.tvChannel.tvChannel(command.command))

  send_command(device, build_messsage("request", 'ssap://tv/' .. command.command))

end



local function handle_lgmessage(_, device, command)

  log.debug("Message set to " .. command.command, command.args.message)
  
  device:emit_event(cap_lgmsg.message(command.args.message))
  
  send_command(device, build_messsage("request", "ssap://system.notifications/createToast", {message=command.args.message}))
  
end


local function handle_lginput(_, device, command)

  log.debug("Media Input set to " .. command.command, command.args.value)
  
  device:emit_event(cap_lginput.inputsource(command.args.value))
  
  send_command(device, build_messsage("request", "ssap://tv/switchInput", {inputId=command.args.value}))

end

------------------------------------------------------------------------
--                REQUIRED EDGE DRIVER HANDLERS
------------------------------------------------------------------------

-- Lifecycle handler to initialize existing devices AND newly discovered devices
local function device_init(driver, device)
  
  log.debug(device.label .. ": " .. device.device_network_id .. "> INITIALIZING")

  initialized = true

  devices_inited = devices_inited + 1
  
  if not device:get_field('ws_client') then
    device.thread:queue_event(init_connection, device)
  end
  
  log.debug('Exiting device initialization')
end


-- Called when device was just created in SmartThings
local function device_added (driver, device)

  log.info(device.label .. ": " .. device.device_network_id .. "> ADDED")
  
  device:set_field('createtime', socket.gettime())
    
  local lgdevice = newly_added[device.device_network_id]
  if lgdevice then
    device:set_field('WSSaddr', lgdevice.ip .. ':' .. WSSPORT, { ['persist'] = true })
    newly_added[device.device_network_id] = nil
    log.debug('IP stored:', lgdevice.ip)
  end

  
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.tvChannel.tvChannel('1'))
  device:emit_event(cap_lginput.inputsource('HDMI1'))
  device:emit_event(capabilities.audioVolume.volume(50))
  device:emit_event(capabilities.audioMute.mute('unmuted'))
  device:emit_event(cap_lgmsg.message(' '))
  device:emit_event(cap_status.status('Created'))
    
  disco_sem:release()
    
end

-- Called when device was deleted via mobile app
local function device_removed(driver, device)
  
  log.warn(device.id .. ": " .. device.device_network_id .. "> removed")

  shutdown_device(driver, device, 'Device removed')
  
  if #driver:get_devices() == 0 then
    log.warn ('All devices removed')
    initialized = false
  end
  
end


-- Called when SmartThings thinks the device needs provisioning
local function device_doconfigure (_, device)

  log.info ('Device doConfigure lifecycle invoked')

end


local function handler_driverchanged(driver, device, event, args)

  log.debug ('*** Driver changed handler invoked ***')

end

local function shutdown_handler(driver, event)

  if event == 'shutdown' then

    log.warn ('Shutting down all devices')
    local device_list = driver:get_devices()
    for _, device in ipairs(device_list) do
      shutdown_device(driver, device, 'Driver shutdown')
    end
  end
end


local function handler_infochanged (driver, device, event, args)

  log.debug ('Info changed handler invoked')
  
  -- Did preferences change?
  if args.old_st_store.preferences then
    
    if args.old_st_store.preferences.freq ~= device.preferences.freq then
      log.info ('Refresh interval changed to: ', device.preferences.freq)
      reset_refresh_timer(device)
    end
  end
  
end


-- Device discovery handler
local function discovery_handler(driver, _, should_continue)
  
  log.info("Starting discovery")
  local known_devices = {}
  local found_devices = {}

  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    known_devices[device.device_network_id] = true
  end
  
  local retries = 5

  while (retries > 0) and should_continue() do
    discovery.find(nil, function(lgdevice)
      local uuid = lgdevice.uuid
      local ip = lgdevice.ip
      if not known_devices[uuid] and not found_devices[uuid] then
      
        local profile = DEVICE_PROFILE

        local name = (lgdevice.name or "LG TV")

        -- add device
        local create_device_msg = {
          type = "LAN",
          device_network_id = uuid,
          label = "LG TV " .. lgdevice.model,
          profile = profile,
          manufacturer = "LG",
          model = lgdevice.model,
          vendor_provided_label = "LG TV",
        }
        log.info_with({hub_logs = true},
          string.format("Create device with: %s", utils.stringify_table(create_device_msg)))
        assert(driver:try_create_device(create_device_msg))
        found_devices[uuid] = true
        newly_added[uuid] = lgdevice
      else
        log.info(string.format("Discovered already known device %s", id))
      end
    end)
    
    retries = retries - 1
  end
  log.info("Ending discovery")
end


-----------------------------------------------------------------------
--        DRIVER MAINLINE: Build driver context table
-----------------------------------------------------------------------
thisDriver = Driver("thisDriver", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    driverSwitched = handler_driverchanged,
    infoChanged = handler_infochanged,
    doConfigure = device_doconfigure,
    removed = device_removed
  },
  driver_lifecycle = shutdown_handler,
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch,
      [capabilities.switch.commands.off.NAME] = handle_switch,
    },
    [capabilities.tvChannel.ID] = {
      [capabilities.tvChannel.commands.setTvChannel.NAME] = handle_channel,
      [capabilities.tvChannel.commands.channelUp.NAME] = handle_channel,
      [capabilities.tvChannel.commands.channelDown.NAME] = handle_channel
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.setVolume.NAME] = handle_volume
    },
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.setMute.NAME] = handle_mute,
      [capabilities.audioMute.commands.mute.NAME] = handle_mute,
      [capabilities.audioMute.commands.unmute.NAME] = handle_mute
    },
    [capabilities.mediaPresets.ID] = {
      [capabilities.mediaPresets.commands.playPreset.NAME] = handle_app,
    },
    [cap_lgmsg.ID] = {
      [cap_lgmsg.commands.setMessage.NAME] = handle_lgmessage
    },
    [cap_lginput.ID] = {
      [cap_lginput.commands.setInputSource.NAME] = handle_lginput
    },
  }
})

log.info ('LG TV Driver Started')

-- start ping monitor
thisDriver:call_on_schedule(120, pingmonitor)

disco_sem = semaphore()

thisDriver:run()
