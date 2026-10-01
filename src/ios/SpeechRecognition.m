// https://developer.apple.com/library/prerelease/content/samplecode/SpeakToMe/Listings/SpeakToMe_ViewController_swift.html
// http://robusttechhouse.com/introduction-to-native-speech-recognition-for-ios/
// https://www.appcoda.com/siri-speech-framework/

#import "SpeechRecognition.h"

#import <Cordova/CDV.h>
#import <Speech/Speech.h>

#define DEFAULT_LANGUAGE @"en-US"
#define DEFAULT_MATCHES 5

#define MESSAGE_MISSING_PERMISSION @"Missing permission"
#define MESSAGE_ACCESS_DENIED @"User denied access to speech recognition"
#define MESSAGE_RESTRICTED @"Speech recognition restricted on this device"
#define MESSAGE_NOT_DETERMINED @"Speech recognition not determined on this device"
#define MESSAGE_ACCESS_DENIED_MICROPHONE @"User denied access to microphone"
#define MESSAGE_ONGOING @"Ongoing speech recognition"
#define MESSAGE_NOT_AVAILABLE @"Speech recognition is not available for the requested language"
#define MESSAGE_NO_AUDIO_INPUT @"No audio input available"

@interface SpeechRecognition()

@property (strong, nonatomic) SFSpeechRecognizer *speechRecognizer;
@property (strong, nonatomic) AVAudioEngine *audioEngine;
@property (strong, nonatomic) SFSpeechAudioBufferRecognitionRequest *recognitionRequest;
@property (strong, nonatomic) SFSpeechRecognitionTask *recognitionTask;
@property (strong, nonatomic) NSString *previousAudioCategory;
@property (assign, nonatomic) AVAudioSessionCategoryOptions previousAudioCategoryOptions;
@property (strong, nonatomic) NSString *previousAudioMode;

@end


@implementation SpeechRecognition

- (void)isRecognitionAvailable:(CDVInvokedUrlCommand*)command {
    BOOL available = NO;

    if ([SFSpeechRecognizer class]) {
        SFSpeechRecognizer *recognizer = [[SFSpeechRecognizer alloc] init];
        available = (recognizer != nil && recognizer.isAvailable);
    }

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:available];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)startListening:(CDVInvokedUrlCommand*)command {
    if ( self.audioEngine.isRunning ) {
        [self sendError:MESSAGE_ONGOING command:command];
        return;
    }

    NSLog(@"startListening()");

    SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];
    if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        NSLog(@"startListening() speech recognition access not authorized");
        [self sendError:MESSAGE_MISSING_PERMISSION command:command];
        return;
    }

    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted){
        // The permission handler may run on an arbitrary queue; AVAudioEngine and
        // the recognizer must be set up from the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!granted) {
                NSLog(@"startListening() microphone access not authorized");
                [self sendError:MESSAGE_ACCESS_DENIED_MICROPHONE command:command];
                return;
            }
            [self startRecognitionWithCommand:command];
        });
    }];
}

- (void)startRecognitionWithCommand:(CDVInvokedUrlCommand*)command {
    if ( self.audioEngine.isRunning ) {
        [self sendError:MESSAGE_ONGOING command:command];
        return;
    }

    NSString* language = [command argumentAtIndex:0 withDefault:DEFAULT_LANGUAGE];
    if (![language isKindOfClass:[NSString class]] || language.length == 0) {
        language = DEFAULT_LANGUAGE;
    }
    int matches = [[command argumentAtIndex:1 withDefault:@(DEFAULT_MATCHES)] intValue];
    if (matches <= 0) {
        matches = DEFAULT_MATCHES;
    }
    BOOL showPartial = [[command argumentAtIndex:3 withDefault:@(NO)] boolValue];

    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:language];
    self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];

    // Unsupported locale or recognizer temporarily unavailable: the task would
    // never call back, so report it now.
    if (self.speechRecognizer == nil || !self.speechRecognizer.isAvailable) {
        NSLog(@"startListening() recognizer not available for locale %@", language);
        [self sendError:MESSAGE_NOT_AVAILABLE command:command];
        return;
    }

    // Cancel the previous task if it's running.
    if ( self.recognitionTask ) {
        [self.recognitionTask cancel];
        self.recognitionTask = nil;
    }

    NSError *audioError = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    // Keep the app's original configuration if a previous session was not torn down yet.
    if (self.previousAudioCategory == nil) {
        self.previousAudioCategory = audioSession.category;
        self.previousAudioCategoryOptions = audioSession.categoryOptions;
        self.previousAudioMode = audioSession.mode;
    }

    // DefaultToSpeaker is only valid with PlayAndRecord; with the Record category
    // setCategory fails and the session is left unconfigured.
    if (![audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                       withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker
                             error:&audioError]
        || ![audioSession setMode:AVAudioSessionModeDefault error:&audioError]
        || ![audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&audioError]) {
        NSLog(@"startListening() audio session error: %@", audioError.description);
        [self restoreAudioSession];
        [self sendError:audioError.localizedDescription command:command];
        return;
    }

    self.audioEngine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *inputNode = self.audioEngine.inputNode;
    AVAudioFormat *format = [inputNode outputFormatForBus:0];

    // Installing a tap with a 0 Hz format raises an exception (e.g. no microphone).
    if (format.sampleRate <= 0 || format.channelCount == 0) {
        NSLog(@"startListening() no audio input available");
        self.audioEngine = nil;
        [self restoreAudioSession];
        [self sendError:MESSAGE_NO_AUDIO_INPUT command:command];
        return;
    }

    self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    self.recognitionRequest.shouldReportPartialResults = showPartial;

    SFSpeechAudioBufferRecognitionRequest *request = self.recognitionRequest;
    __block BOOL finished = NO;

    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        if (finished) {
            return;
        }

        BOOL isFinal = result.isFinal;

        if ( result ) {
            NSMutableArray *resultArray = [[NSMutableArray alloc] init];

            for ( SFTranscription *transcription in result.transcriptions ) {
                if (resultArray.count >= (NSUInteger)matches) {
                    break;
                }
                [resultArray addObject:transcription.formattedString];
            }

            NSArray *transcriptions = [NSArray arrayWithArray:resultArray];

            NSLog(@"startListening() recognitionTask result array: %@", transcriptions.description);

            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:transcriptions];
            // Keep the callback open for partial results until the final one arrives.
            [pluginResult setKeepCallbackAsBool:(showPartial && !isFinal && !error)];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }

        if ( error || isFinal ) {
            finished = YES;

            if ( error && !result ) {
                NSLog(@"startListening() recognitionTask error: %@", error.description);
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            } else {
                NSLog(@"startListening() recognitionTask isFinal");
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                // Only tear down if a newer session has not replaced this one.
                if (self.recognitionRequest == request) {
                    [self stopAudio];
                    self.recognitionRequest = nil;
                    self.recognitionTask = nil;
                }
            });
        }
    }];

    [inputNode installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [request appendAudioPCMBuffer:buffer];
    }];

    [self.audioEngine prepare];
    NSError *engineError = nil;
    if (![self.audioEngine startAndReturnError:&engineError]) {
        NSLog(@"startListening() audio engine error: %@", engineError.description);
        finished = YES;
        [self.recognitionTask cancel];
        [self stopAudio];
        self.recognitionRequest = nil;
        self.recognitionTask = nil;
        [self sendError:engineError.localizedDescription command:command];
    }
}

- (void)stopListening:(CDVInvokedUrlCommand*)command {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"stopListening()");

        if ( self.audioEngine.isRunning ) {
            [self.audioEngine stop];
            [self.audioEngine.inputNode removeTapOnBus:0];
        }
        // Lets the recognizer deliver the final result for the audio captured so far.
        [self.recognitionRequest endAudio];

        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    });
}

- (void)getSupportedLanguages:(CDVInvokedUrlCommand*)command {
    NSSet<NSLocale *> *supportedLocales = [SFSpeechRecognizer supportedLocales];

    NSMutableArray *localesArray = [[NSMutableArray alloc] init];

    for(NSLocale *locale in supportedLocales) {
        [localesArray addObject:[locale localeIdentifier]];
    }

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:localesArray];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)hasPermission:(CDVInvokedUrlCommand*)command {
    SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];
    BOOL speechAuthGranted = (status == SFSpeechRecognizerAuthorizationStatusAuthorized);

    // Read the current state only: requestRecordPermission would prompt the user.
    BOOL microphoneGranted = ([[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionGranted);

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:(speechAuthGranted && microphoneGranted)];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)requestPermission:(CDVInvokedUrlCommand*)command {
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status){
        dispatch_async(dispatch_get_main_queue(), ^{
            CDVPluginResult *pluginResult = nil;
            BOOL speechAuthGranted = NO;

            switch (status) {
                case SFSpeechRecognizerAuthorizationStatusAuthorized:
                    speechAuthGranted = YES;
                    break;
                case SFSpeechRecognizerAuthorizationStatusDenied:
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_ACCESS_DENIED];
                    break;
                case SFSpeechRecognizerAuthorizationStatusRestricted:
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_RESTRICTED];
                    break;
                case SFSpeechRecognizerAuthorizationStatusNotDetermined:
                default:
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_NOT_DETERMINED];
                    break;
            }

            if (!speechAuthGranted) {
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                return;
            }

            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted){
                CDVPluginResult *pluginResult = nil;

                if (granted) {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                } else {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_ACCESS_DENIED_MICROPHONE];
                }

                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }];
        });
    }];
}

#pragma mark - Helpers

- (void)sendError:(NSString *)message command:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:message];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stopAudio {
    if (self.audioEngine) {
        if (self.audioEngine.isRunning) {
            [self.audioEngine stop];
        }
        [self.audioEngine.inputNode removeTapOnBus:0];
        self.audioEngine = nil;
    }
    [self restoreAudioSession];
}

// Give the audio session back to the app (and to other apps) once recognition ends,
// so audio playback is not left muted or routed for recording.
- (void)restoreAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];

    if (self.previousAudioCategory) {
        [audioSession setCategory:self.previousAudioCategory withOptions:self.previousAudioCategoryOptions error:nil];
        self.previousAudioCategory = nil;
    }
    if (self.previousAudioMode) {
        [audioSession setMode:self.previousAudioMode error:nil];
        self.previousAudioMode = nil;
    }
}

- (void)onReset {
    [self.recognitionTask cancel];
    [self stopAudio];
    self.recognitionRequest = nil;
    self.recognitionTask = nil;
}

@end
