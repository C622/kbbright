// kbbright — keyboard backlight control for Apple Silicon MacBooks.
//
//   kbbright get            print current level (0.0–1.0)
//   kbbright set <0..1>     set level
//   kbbright up | down      step by 1/16 (same steps as the old hardware keys)
//   kbbright daemon         stay running and turn Shift/Option + the screen
//                           brightness keys (or F13/F14) into keyboard
//                           backlight down/up
//
// Set KBBRIGHT_DEBUG=1 to log every brightness key event to stderr.
//
// Uses the private CoreBrightness KeyboardBrightnessClient class (what Control
// Center uses). Hotkeys use a CGEventTap, which needs Accessibility
// permission (System Settings → Privacy & Security → Accessibility).

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <dlfcn.h>
#import <objc/message.h>

static const float kStep = 1.0f / 16.0f;
static const int kFadeMs = 120;

static id gClient;
static unsigned long long gKeyboardID;

static BOOL setupClient(void) {
    if (!dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)) return NO;
    Class cls = NSClassFromString(@"KeyboardBrightnessClient");
    if (!cls) return NO;
    gClient = [cls new];
    NSArray *ids = ((id (*)(id, SEL))objc_msgSend)(gClient, NSSelectorFromString(@"copyKeyboardBacklightIDs"));
    if (ids.count == 0) return NO;
    gKeyboardID = [ids.firstObject unsignedLongLongValue];
    return YES;
}

static float getLevel(void) {
    return ((float (*)(id, SEL, unsigned long long))objc_msgSend)(
        gClient, NSSelectorFromString(@"brightnessForKeyboard:"), gKeyboardID);
}

static void setLevel(float level) {
    level = fminf(1.0f, fmaxf(0.0f, level));
    ((BOOL (*)(id, SEL, float, int, BOOL, unsigned long long))objc_msgSend)(
        gClient, NSSelectorFromString(@"setBrightness:fadeSpeed:commit:forKeyboard:"),
        level, kFadeMs, YES, gKeyboardID);
}

static void step(int direction) {
    // Snap to the 1/16 grid so repeated presses land on consistent levels.
    float steps = roundf(getLevel() / kStep) + direction;
    setLevel(steps * kStep);
}

#pragma mark - Hotkey daemon
//
// The keys may arrive either as plain F13/F14 key codes or, when the system
// treats them as screen-brightness keys, as NX_SYSDEFINED media-key events.
// A session event tap sees both and can swallow them before macOS changes the
// display brightness. This needs Accessibility permission.

#define NX_SYSDEFINED_TYPE 14
#define NX_SUBTYPE_AUX_CONTROL 8
#define NX_KEYTYPE_BRIGHTNESS_UP 2
#define NX_KEYTYPE_BRIGHTNESS_DOWN 3

static CFMachPortRef gTap;
static BOOL gDebug;

static BOOL wantsKeyboard(CGEventFlags flags) {
    BOOL mod = (flags & (kCGEventFlagMaskShift | kCGEventFlagMaskAlternate)) != 0;
    BOOL other = (flags & (kCGEventFlagMaskCommand | kCGEventFlagMaskControl)) != 0;
    return mod && !other;
}

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *ctx) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(gTap, true);
        return event;
    }
    CGEventFlags flags = CGEventGetFlags(event);

    if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        int64_t code = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        if (code != kVK_F13 && code != kVK_F14) return event;
        if (gDebug) NSLog(@"key %s code=%lld flags=0x%llx", type == kCGEventKeyDown ? "down" : "up", code, flags);
        if (!wantsKeyboard(flags)) return event;
        if (type == kCGEventKeyDown) step(code == kVK_F14 ? 1 : -1);
        return NULL;
    }

    if (type == NX_SYSDEFINED_TYPE) {
        NSEvent *e = [NSEvent eventWithCGEvent:event];
        if (e.subtype != NX_SUBTYPE_AUX_CONTROL) return event;
        int key = (int)((e.data1 & 0xFFFF0000) >> 16);
        BOOL down = ((e.data1 & 0xFF00) >> 8) == 0xA;
        if (key != NX_KEYTYPE_BRIGHTNESS_UP && key != NX_KEYTYPE_BRIGHTNESS_DOWN) return event;
        if (gDebug) NSLog(@"media brightness %s %s flags=0x%llx", key == NX_KEYTYPE_BRIGHTNESS_UP ? "up" : "down",
              down ? "down" : "up", flags);
        if (!wantsKeyboard(flags)) return event;
        if (down) step(key == NX_KEYTYPE_BRIGHTNESS_UP ? 1 : -1);
        return NULL;
    }
    return event;
}

static BOOL installTap(void) {
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) |
                       CGEventMaskBit(NX_SYSDEFINED_TYPE);
    gTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                            mask, tapCallback, NULL);
    if (!gTap) return NO;
    CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, gTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
    CGEventTapEnable(gTap, true);
    NSLog(@"event tap installed");
    return YES;
}

static int runDaemon(void) {
    gDebug = getenv("KBBRIGHT_DEBUG") != NULL;
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];

    NSDictionary *opts = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @YES };
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts) || !installTap()) {
        // Keep retrying so granting Accessibility takes effect without a restart.
        NSLog(@"waiting for Accessibility permission for %s", NSProcessInfo.processInfo.arguments[0].UTF8String);
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) {
            if (AXIsProcessTrusted() && installTap()) [t invalidate];
        }];
    }
    [NSApp run];
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (!setupClient()) {
            fprintf(stderr, "kbbright: no keyboard backlight found\n");
            return 1;
        }
        NSString *cmd = argc > 1 ? @(argv[1]) : @"";
        if ([cmd isEqualToString:@"get"]) {
            printf("%.4f\n", getLevel());
        } else if ([cmd isEqualToString:@"set"] && argc > 2) {
            setLevel(atof(argv[2]));
        } else if ([cmd isEqualToString:@"up"]) {
            step(1);
        } else if ([cmd isEqualToString:@"down"]) {
            step(-1);
        } else if ([cmd isEqualToString:@"daemon"]) {
            return runDaemon();
        } else {
            fprintf(stderr, "usage: kbbright get | set <0..1> | up | down | daemon\n");
            return 2;
        }
        // Let the fade/commit reach corebrightnessd before exiting.
        if (![cmd isEqualToString:@"get"]) usleep((kFadeMs + 50) * 1000);
    }
    return 0;
}
