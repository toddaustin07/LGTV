# LG TV Driver
SmartThings Edge Driver for LG TVs.  Includes these features:
* Turn TV on (with WoL) and off
* Control volume level & mute
* Select input source
* Select app
* Change channel up and down
* Display a message on TV screen
* Automatically update SmartThings device with latest TV states at configured frequency (in seconds)

## Pre-requisites
* LG TV
* SmartThings Hub

## Installation

Enroll your hub via [this channel link](https://bestow-regional.api.smartthings.com/invite/Q1jP7BqnNNlL) and select **LG TV V1.0** to install to your hub.

Once the driver is available on your hub, use the SmartThings app to do an **Add device / Scan for nearby devices**.  Any LG TVs found on your local network will be discovered and added as SmartThings devices in the room your hub device is located.

## Configuration
There are 3 options that can be tailored in device Settings:
* Refresh Frequency
  
  This determines how often the driver will poll your TV in order to reflect any state updates
* WOL MAC Address
  
  This must be configured with your TV's MAC address if you want to be able to turn it on
* WOL Broadcast Address
  
  Normally this field should not be changed, but is provided in case of unique network requirements

## Controls screen
* Power switch: turn TV on or off
* Volume: adjust volume level or enable/disable mute
* Media Input Source:  select from HDMI1, HDMI2, HDMI3, AV, Component
* Play a favorite:  select from the list of apps available on your TV
* Channel: change channel up or down
* Message: enter text you want displayed on a TOAST message on the TV screen
* Status: shows the current connection status with the TV, or error messages of applicable

## Routines
* On/off, volume, mute are available for 'If' conditions
* All controls but channel up/down are available for Routine 'Then' actions (this appears to be a SmartThings capability issue at the moment)

## Attribution
Credit goes to Karl Lattimer for providing the undocumented commands that made this driver possible:  [Github link](https://github.com/klattimer/LGWebOSRemote/tree/master/LGTV)
