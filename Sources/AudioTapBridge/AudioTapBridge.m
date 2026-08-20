#import "AudioTapBridge.h"

NSString *_Nullable VCInstallAudioTap(
    AVAudioNode *node,
    AVAudioNodeBus bus,
    AVAudioFrameCount bufferSize,
    AVAudioFormat *format,
    AVAudioNodeTapBlock block) {
  @try {
    [node installTapOnBus:bus
               bufferSize:bufferSize
                   format:format
                    block:block];
    return nil;
  } @catch (NSException *exception) {
    return exception.reason ?: exception.name;
  }
}
