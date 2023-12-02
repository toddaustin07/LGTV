# LG TV Driver
SmartThings Edge Driver for LG TVs.  Includes these features:
* Turn TV on (with WoL) and off
* Control volume level & mute
* Select input source
* Select app
* Change channel up and down
* Display a message on TV screen
* Automatically update SmartThings device with latest TV states at configured frequency (in seconds)

## Caveats
I have no idea how many LG TV models will work with this driver, but devices with firmware major version 4, product name "webOSTV 2.0" should be OK.

This driver relies on a set of undocumented commands to control the TV and retrieve state updates.  This API was meant to be used internally by LG and therefore could stop working at their whim.

## Pre-requisites
* LG TV
* SmartThings Hub

## Installation

Enroll your hub via [this channel link](https://bestow-regional.api.smartthings.com/invite/Q1jP7BqnNNlL) and select **LG TV V1.1** to install to your hub.

Turn on your LG TVs (this is needed for initial registration; see below)

Once the driver is available on your hub, use the SmartThings app to do an **Add device / Scan for nearby devices**.  Any LG TVs found on your local network will be discovered and added as SmartThings devices in the room your hub device is located.

When the new TV device(s) is/are created, a one-time registration handshake must be completed with the discovered TVs.  You should see a message pop up on your TV(s) that you'll need to respond to.  Once this is completed, your SmartThings device should successfully initialize.

## Configuration
There are 3 options that can be tailored in device Settings:
* Refresh Frequency
  
  This determines how often the driver will poll your TV in order to reflect any state updates
* Volume Change Interval

  Enter a numeric value from 1 to 20 to set how many times to 'bump' the volume each time the Volume Up or Volume Down button is pressed.
* WOL MAC Address
  
  This must be configured with your TV's MAC address if you want to be able to turn it on
* WOL Broadcast Address
  
  Normally this field should not be changed, but is provided in case of unique network requirements

## Controls screen
* Power switch: turn TV on or off
* Volume: adjust volume level (slider) or enable/disable mute
* Volume Up / Volume Down:  buttons to bump volume; work with external speakers; also see Configuration for setting up/down interval amount
* Media Input Source:  select from HDMI1, HDMI2, HDMI3, AV, Component
* Active App: displays the current app
* Change App:  select from the list of apps available on your TV
* Current Channel: displays the current channel number - channel name
* Channel: change channel up or down
* Message: enter text you want displayed on a TOAST message on the TV screen
* Status: shows the current connection status with the TV, or error messages of applicable

## Routines
* On/off, volume level, mute, media input source, current app, current channel number are available for 'If' conditions
* All controls but channel up/down are available for Routine 'Then' actions (this appears to be a SmartThings capability issue at the moment)

## Attribution
Credit goes to Karl Lattimer for providing the undocumented commands that made this driver possible:  [Github link](https://github.com/klattimer/LGWebOSRemote/tree/master/LGTV)
