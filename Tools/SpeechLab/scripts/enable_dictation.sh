#!/bin/bash
# Turn on Siri + Dictation for the runner user so SFSpeechRecognizer (server and on-device) is allowed.
# (Without this the on-device recognizer fails with kLSRErrorDomain 201 "Siri and Dictation are disabled".)
defaults write com.apple.assistant.support "Dictation Enabled" -bool true
defaults write com.apple.assistant.support "Assistant Enabled" -bool true
defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2
defaults write com.apple.HIToolbox AppleDictationAutoEnable -int 1
defaults write com.apple.Siri UserHasDeclinedEnable -bool false
defaults write com.apple.Siri StatusMenuVisible -bool false
sudo defaults write /Library/Preferences/com.apple.assistant.support "Dictation Enabled" -bool true
killall -9 assistantd corespeechd localspeechrecognition speechrecognitiond SiriNCService 2>/dev/null || true
echo "dictation prefs set"
