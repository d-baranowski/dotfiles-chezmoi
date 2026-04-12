#!/bin/bash
# Disable the alert sound that plays when pressing an invalid key.

defaults write -g com.apple.sound.beep.feedback -bool false
defaults write -g com.apple.sound.uiaudio.enabled -int 0
