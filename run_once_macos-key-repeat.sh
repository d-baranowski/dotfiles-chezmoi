#!/bin/bash
# Set key repeat rate to roughly twice the macOS default speed.
# KeyRepeat: default 6, lower = faster (minimum 1)
# InitialKeyRepeat: default 25, lower = shorter delay before repeat starts
# Requires logout or restart to take effect.

defaults write -g KeyRepeat -int 3
defaults write -g InitialKeyRepeat -int 25
