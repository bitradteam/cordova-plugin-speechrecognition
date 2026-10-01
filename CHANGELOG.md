# Changelog

## v1.3.0

- Android: results of `startListening` are no longer lost when another method (e.g. `stopListening`) is called while listening
- Android: `requestPermission` and `getSupportedLanguages` answer on their own callbacks
- Android: `getSupportedLanguages` uses an explicit intent (works on Android 8+) and no longer reuses a stale callback
- Android: duplicate partial results are filtered correctly
- Android: default language is a BCP 47 tag (`en-US` instead of `en_US`)
- Android: cancel an ongoing session before starting a new one, release the recognizer on destroy
- Android: package visibility query for the popup activity (Android 11+)
- Android: do not report "invalid action" after an error has already been sent
- iOS: valid audio session category (`Record` + `DefaultToSpeaker` was rejected by the system); previous session restored afterwards
- iOS: audio engine set up on the main thread; errors from the audio session/engine are reported instead of silently ignored
- iOS: error when the language is not supported instead of never calling back
- iOS: partial results callback is closed on the final result or on error
- iOS: `hasPermission` no longer prompts the user for microphone access
- iOS: `stopListening` runs on the main thread; recognition is cleaned up on page reload
- iOS: configurable usage descriptions (`MICROPHONE_USAGE_DESCRIPTION`, `SPEECH_RECOGNITION_USAGE_DESCRIPTION`)

## v1.2.0

- Android: add `stopListening` [by Simone Compagnone]
- Android: enable partial results [by Simone Compagnone]

## v1.1.2

- iOS: `startListening` do not run in background
- iOS: `startListening` check existing process

## v1.1.1

- Android: use Cordova Permissions API
- Android: drop Android Support Library requirement

## v1.1.0

- Android: recognition is runnable in the background without popup window ( option `showPopup` )
- modify signature of function `startListening`
- Android: real callbacks for `requestPermission`

## v1.0.5

- iOS: use `AVAudioSessionCategoryPlayAndRecord` mode
- iOS: run `startListening` and `stopListening` in the background

## v1.0.4

- iOS: return partial results ( option `showPartial` )

## v1.0.3

- initial release of `cordova-plugin-speechrecognition`
