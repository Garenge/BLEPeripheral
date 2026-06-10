#import "AppDelegate.h"
#import "BLEPeripheralController.h"

static NSUInteger const kMaxLogLineCount = 300;

@interface AppDelegate ()

@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextView *logTextView;
@property (nonatomic, strong) NSButton *clearLogButton;
@property (nonatomic, strong) NSButton *releaseClientButton;
@property (nonatomic, strong) BLEPeripheralController *peripheralController;
@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self applyLightAppearance];
    self.logLines = [NSMutableArray array];

    [self buildWindow];

    __weak typeof(self) weakSelf = self;
    self.peripheralController = [[BLEPeripheralController alloc] initWithLogHandler:^(NSString *message) {
        [weakSelf appendLog:message];
    }];
    [self appendLog:@"[SYS] Log window ready"];
    [self.peripheralController start];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)applyLightAppearance {
    if (@available(macOS 10.14, *)) {
        NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        [NSApp setAppearance:light];
    }
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
    if (@available(macOS 10.14, *)) {
        self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    }
    [self.window center];

    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    NSTextField *titleLabel = [NSTextField labelWithString:@"macOS BLE Peripheral Simulator"];
    titleLabel.font = [NSFont boldSystemFontOfSize:20];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *infoLabel = [NSTextField labelWithString:@"FFF1: 00AA+原内容 | 手机须先开 Notify 才能自动收回复(不必Read)"];
    infoLabel.font = [NSFont systemFontOfSize:13];
    infoLabel.textColor = NSColor.secondaryLabelColor;
    infoLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.borderType = NSBezelBorder;
    scrollView.hasVerticalScroller = YES;

    self.clearLogButton = [NSButton buttonWithTitle:@"Clear Logs" target:self action:@selector(clearLogs:)];
    self.clearLogButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.clearLogButton.bezelStyle = NSBezelStyleRounded;

    self.releaseClientButton = [NSButton buttonWithTitle:@"Release Client" target:self action:@selector(releaseClient:)];
    self.releaseClientButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.releaseClientButton.bezelStyle = NSBezelStyleRounded;

    self.logTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.logTextView.editable = NO;
    self.logTextView.selectable = YES;
    self.logTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.logTextView.textColor = [NSColor blackColor];
    self.logTextView.backgroundColor = [NSColor whiteColor];
    self.logTextView.minSize = NSMakeSize(0, 0);
    self.logTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    self.logTextView.verticallyResizable = YES;
    self.logTextView.horizontallyResizable = NO;
    self.logTextView.textContainerInset = NSMakeSize(6, 6);
    self.logTextView.textContainer.widthTracksTextView = YES;
    scrollView.documentView = self.logTextView;

    [contentView addSubview:titleLabel];
    [contentView addSubview:infoLabel];
    [contentView addSubview:self.releaseClientButton];
    [contentView addSubview:self.clearLogButton];
    [contentView addSubview:scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:contentView.trailingAnchor constant:-20],

        [infoLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [infoLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [infoLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [self.releaseClientButton.topAnchor constraintEqualToAnchor:infoLabel.bottomAnchor constant:12],
        [self.releaseClientButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],

        [self.clearLogButton.centerYAnchor constraintEqualToAnchor:self.releaseClientButton.centerYAnchor],
        [self.clearLogButton.leadingAnchor constraintEqualToAnchor:self.releaseClientButton.trailingAnchor constant:10],
        [self.clearLogButton.trailingAnchor constraintLessThanOrEqualToAnchor:contentView.trailingAnchor constant:-20],

        [scrollView.topAnchor constraintEqualToAnchor:self.releaseClientButton.bottomAnchor constant:12],
        [scrollView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [scrollView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [scrollView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-20],
    ]];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activate];
}

- (void)appendLog:(NSString *)message {
    void (^append)(void) = ^{
        if (!self.logTextView) {
            return;
        }
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:NSDate.date], message];
        [self.logLines addObject:line];
        [self trimLogLinesIfNeeded];
        [self renderLogLines];
    };

    if ([NSThread isMainThread]) {
        append();
    } else {
        dispatch_async(dispatch_get_main_queue(), append);
    }
}

- (void)clearLogs:(id)sender {
    [self.logLines removeAllObjects];
    [self renderLogLines];
}

- (void)releaseClient:(id)sender {
    [self.peripheralController releaseActiveClient];
}

- (void)trimLogLinesIfNeeded {
    while (self.logLines.count > kMaxLogLineCount) {
        [self.logLines removeObjectAtIndex:0];
    }
}

- (void)renderLogLines {
    if (!self.logTextView) {
        return;
    }
    NSString *text = [self.logLines componentsJoinedByString:@""];
    NSDictionary *attributes = @{
        NSFontAttributeName: self.logTextView.font ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor blackColor],
    };
    NSAttributedString *content = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    [[self.logTextView textStorage] setAttributedString:content];

    NSUInteger length = self.logTextView.textStorage.length;
    if (length > 0) {
        [self.logTextView scrollRangeToVisible:NSMakeRange(length - 1, 1)];
    }
    [self.logTextView setNeedsDisplay:YES];
}

@end
