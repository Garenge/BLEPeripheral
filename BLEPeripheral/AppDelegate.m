#import "AppDelegate.h"
#import "BLEPeripheralController.h"

@interface AppDelegate ()

@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextView *logTextView;
@property (nonatomic, strong) BLEPeripheralController *peripheralController;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];

    __weak typeof(self) weakSelf = self;
    self.peripheralController = [[BLEPeripheralController alloc] initWithLogHandler:^(NSString *message) {
        [weakSelf appendLog:message];
    }];
    [self.peripheralController start];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 760, 520);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:(NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskMiniaturizable |
                                                        NSWindowStyleMaskResizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"BLE Peripheral Demo";
    [self.window center];

    NSView *contentView = self.window.contentView;

    NSTextField *titleLabel = [NSTextField labelWithString:@"macOS BLE Peripheral Simulator"];
    titleLabel.font = [NSFont boldSystemFontOfSize:20];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *infoLabel = [NSTextField labelWithString:@"Device name: MacBLE-Demo | Service: FFF0 | Read/Write/Notify: FFF1"];
    infoLabel.font = [NSFont systemFontOfSize:13];
    infoLabel.textColor = NSColor.secondaryLabelColor;
    infoLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.borderType = NSBezelBorder;
    scrollView.hasVerticalScroller = YES;

    self.logTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.logTextView.editable = NO;
    self.logTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.logTextView.textColor = NSColor.labelColor;
    self.logTextView.backgroundColor = NSColor.textBackgroundColor;
    scrollView.documentView = self.logTextView;

    [contentView addSubview:titleLabel];
    [contentView addSubview:infoLabel];
    [contentView addSubview:scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:contentView.trailingAnchor constant:-20],

        [infoLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [infoLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [infoLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [scrollView.topAnchor constraintEqualToAnchor:infoLabel.bottomAnchor constant:16],
        [scrollView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [scrollView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [scrollView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-20],
    ]];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activate];
}

- (void)appendLog:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:NSDate.date], message];

        NSTextStorage *textStorage = self.logTextView.textStorage;
        [textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:line]];
        [self.logTextView scrollRangeToVisible:NSMakeRange(textStorage.length, 0)];
    });
}

@end
