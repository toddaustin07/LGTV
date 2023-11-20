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
  
  Heatmiser neoHub Device Driver - Common routines

--]]

local capabilities = require "st.capabilities"
local stutils = require "st.utils"
local log = require "log"
local json = require "dkjson"


local function disptable(intable, tab, maxlevels, currlevel)

  if not currlevel then; currlevel = 0; end
  currlevel = currlevel + 1
  for key, value in pairs(intable) do
    if type(key) ~= 'table' then
      log.debug (tab .. '  ' .. key, value)
    else
      log.debug (tab .. '  ', key, value)
    end
    if (type(value) == 'table') and (currlevel < maxlevels) then
      disptable(value, '  ' .. tab, maxlevels, currlevel)
    end
  end
end



return {

    
  disptable = function(intable, tab, maxlevels, currlevel)

    if not currlevel then; currlevel = 0; end
    currlevel = currlevel + 1
    for key, value in pairs(intable) do
      if type(key) ~= 'table' then
        log.debug (tab .. '  ' .. key, value)
      else
        log.debug (tab .. '  ', key, value)
      end
      if (type(value) == 'table') and (currlevel < maxlevels) then
        disptable(value, '  ' .. tab, maxlevels, currlevel)
      end
    end
  end,
  
  
  validate_address = function(lanAddress)

    if lanAddress then

      local valid = true
      
      local chunks = {lanAddress:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
      if #chunks == 4 then
        for i, v in pairs(chunks) do
          if tonumber(v) > 255 then 
            valid = false
            break
          end
        end
      else
        valid = false
      end
      
      return (valid)
    else
      return (false)
    end
  end,
  
  
  build_html = function(list)

    if #list > 0 then
  
      table.sort(list)
  
      local html_list = ''

      for _, item in ipairs(list) do
        html_list = html_list .. '<tr><td>' .. item .. '</td></tr>\n'
      end

      local html =  {
                      '<!DOCTYPE html>\n',
                      '<HTML>\n',
                      '<HEAD>\n',
                      '<style>\n',
                      'table, td {\n',
                      '  border: 1px solid black;\n',
                      '  border-collapse: collapse;\n',
                      '  font-size: 14px;\n',
                      '  padding: 3px;\n',
                      '}\n',
                      '</style>\n',
                      '</HEAD>\n',
                      '<BODY>\n',
                      '<table>\n',
                      html_list,
                      '</table>\n',
                      '</BODY>\n',
                      '</HTML>\n'
                    }
        
      return (table.concat(html))
    
    else
      return (' ')
    end
  end,

  
  decode_json = function(data)
  
    local json_table, pos, err = json.decode(data, 1, nil)
  
    if err then
      log.error ('Failed to decode JSON:', data, pos, err)
      return
    else
      return json_table
    end
  end,
  
  encode_json = function(data)
  
    return json.encode(data)
  
  end,
  
  create_neodevice = function(hubdevice, name, neoid)
  
    local dtype = hubdevice:get_field('neodevice_types')[name]
    
    if not typetable[dtype] then
      log.warn (string.format('Cannot create device named %s; type is unsupported (%s) ', name, dtype))
      return
    end
    
    local MODEL = typetable[dtype].model
    local PROFILE = typetable[dtype].profile
    local LABEL = typetable[dtype].label .. ': ' .. name
    local VENDLABEL = typetable[dtype].label .. '_' .. tostring(neoid)
    
    local ID = hubdevice.device_network_id .. '_' .. typetable[dtype].label .. '_' .. tostring(neoid)
    local MFG_NAME = 'heatmiser'
    
      
    local create_device_msg = {
                                type = "LAN",
                                device_network_id = ID,
                                label = LABEL,
                                profile = PROFILE,
                                manufacturer = MFG_NAME,
                                model = MODEL,
                                vendor_provided_label = VENDLABEL,
                                parent_device_id = hubdevice.id
                              }
                        
    newly_added[ID] = name
                        
    disco_sem:acquire(function()
        log.info (string.format('Creating type %s device: name=%s, neoid=%s; ID=%s', MODEL, name, neoid, ID))
        assert (thisDriver:try_create_device(create_device_msg), "failed to create device")
      end)  
  end,
  
  
  send_command = function(client, token, command, commandid)

    --[[
        Format:
          {"message_type":"hm_get_command_queue","message":"{\"token\":\"{{token}}\",\"COMMANDS\":[{\"COMMAND\":\"{{command}}\",\"COMMANDID\":1}]}"}
          
          command example:  local command = "'GET_ZONES':0"
    --]]
  

    local buildmsg = '{"message_type":"hm_get_command_queue","message":"{\\"token\\":\\"' .. token .. '\\",\\"COMMANDS\\":[{\\"COMMAND\\":\\"{' .. command .. '}\\",\\"COMMANDID\\":' .. tostring(commandid) .. '}]}"}'
    
    log.debug ('Sending websocket message:', buildmsg)
    local ok, close_was_clean, close_code, close_reason = client:send(buildmsg)
    
    if not ok then
      log.error ('Websocket Send failed:')
      log.error (close_was_clean, close_code, close_reason)
    else
      log.info ('Message sent')
    end
  end,
  

  -- for sending setpoint commands to hub
  convert_setpoint_units = function(hubdevice, setpoint)
  
    if (hubdevice.preferences.tempunit == 'F') and (hubdevice:get_field('hubmeta').CORF == 'C') then
      setpoint = stutils.f_to_c(setpoint)
    elseif (hubdevice.preferences.tempunit == 'C') and (hubdevice:get_field('hubmeta').CORF == 'F') then
      setpoint = stutils.c_to_f(setpoint)
    end
    
    return setpoint
  
  end,
  
  -- for received temperatures to compare with cache, which is celsius
  convert_received_temp = function(hubdevice, temp)
  
    if hubdevice:get_field('hubmeta').CORF == 'F' then
      temp = stutils.f_to_c(temp)
    end
    
    return temp
  
  end,
  
  
  is_frost_enabled = function(hubdevice, device)
  
    local frost_setpoints = hubdevice:get_field('frost_setpoints')
    if hubdevice:get_field('hubmeta').CORF == 'C' then
      if frost_setpoints[device:get_field('neoname')] > MAXFROST_C then; return false; end
    elseif frost_setpoints[device:get_field('neoname')] > MAXFROST_F then; return false; end
    
    return true
  
  end,
  
}
