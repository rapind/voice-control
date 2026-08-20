#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs a tap and converts AVFAudio's Objective-C exceptions into an
/// ordinary error message that Swift recovery code can retry.
FOUNDATION_EXPORT NSString *_Nullable VCInstallAudioTap(
    AVAudioNode *node,
    AVAudioNodeBus bus,
    AVAudioFrameCount bufferSize,
    AVAudioFormat *format,
    AVAudioNodeTapBlock block);

NS_ASSUME_NONNULL_END
