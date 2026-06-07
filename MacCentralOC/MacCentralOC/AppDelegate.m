#import "AppDelegate.h"
#import "BLECentralController.h"

@interface AppDelegate ()

@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSPopUpButton *deviceMenu;
@property (nonatomic, strong) NSTextField *payloadField;
@property (nonatomic, strong) NSTextField *pairCodeField;
@property (nonatomic, strong) NSButton *scanButton;
@property (nonatomic, strong) NSButton *connectButton;
@property (nonatomic, strong) NSButton *disconnectButton;
@property (nonatomic, strong) NSButton *readButton;
@property (nonatomic, strong) NSButton *writeButton;
@property (nonatomic, strong) NSButton *pairButton;
@property (nonatomic, strong) NSButton *pingButton;
@property (nonatomic, strong) NSButton *infoButton;
@property (nonatomic, strong) NSButton *telemetryButton;
@property (nonatomic, strong) NSButton *commandButton;
@property (nonatomic, strong) NSTextField *ruleModeLabel;
@property (nonatomic, strong) NSSegmentedControl *ruleModeControl;
@property (nonatomic, strong) NSButton *rawButton;
@property (nonatomic, strong) NSButton *notifyButton;
@property (nonatomic, strong) NSTextView *logTextView;
@property (nonatomic, strong) BLECentralController *centralController;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self applyLightAppearance];
    [self buildWindow];

    __weak typeof(self) weakSelf = self;
    self.centralController = [[BLECentralController alloc] initWithLogHandler:^(NSString *message) {
        [weakSelf appendLog:message];
    }];
    self.centralController.stateHandler = ^{
        [weakSelf refreshControls];
    };
    [self appendLog:@"[SYS] Log window ready"];
    [self refreshControls];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)applyLightAppearance {
    if (@available(macOS 10.14, *)) {
        [NSApp setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
    }
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 860, 560)
                                             styleMask:(NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskMiniaturizable |
                                                        NSWindowStyleMaskResizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"MacCentralOC BLE Central Demo";
    [self.window center];

    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    NSTextField *titleLabel = [self labelWithText:@"macOS Objective-C BLE Central"];
    titleLabel.font = [NSFont boldSystemFontOfSize:20];

    NSTextField *infoLabel = [self labelWithText:@"Scan FFF0 -> Pair code -> token-secured Ping/Info/Echo/Telemetry/Command over FFF1"];
    infoLabel.font = [NSFont systemFontOfSize:13];
    infoLabel.textColor = NSColor.secondaryLabelColor;

    NSStackView *topControls = [self buildTopControls];
    NSStackView *gattControls = [self buildGattControls];
    NSStackView *ruleControls = [self buildRuleControls];
    NSScrollView *logScrollView = [self buildLogView];

    [contentView addSubview:titleLabel];
    [contentView addSubview:infoLabel];
    [contentView addSubview:topControls];
    [contentView addSubview:gattControls];
    [contentView addSubview:ruleControls];
    [contentView addSubview:logScrollView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:contentView.trailingAnchor constant:-20],

        [infoLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [infoLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [infoLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [topControls.topAnchor constraintEqualToAnchor:infoLabel.bottomAnchor constant:16],
        [topControls.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [topControls.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],

        [gattControls.topAnchor constraintEqualToAnchor:topControls.bottomAnchor constant:12],
        [gattControls.leadingAnchor constraintEqualToAnchor:topControls.leadingAnchor],
        [gattControls.trailingAnchor constraintEqualToAnchor:topControls.trailingAnchor],

        [ruleControls.topAnchor constraintEqualToAnchor:gattControls.bottomAnchor constant:12],
        [ruleControls.leadingAnchor constraintEqualToAnchor:gattControls.leadingAnchor],
        [ruleControls.trailingAnchor constraintLessThanOrEqualToAnchor:gattControls.trailingAnchor],

        [logScrollView.topAnchor constraintEqualToAnchor:ruleControls.bottomAnchor constant:16],
        [logScrollView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [logScrollView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [logScrollView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-20],
    ]];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activate];
}

- (NSStackView *)buildTopControls {
    self.scanButton = [self buttonWithTitle:@"Scan" action:@selector(scanTapped:)];
    self.connectButton = [self buttonWithTitle:@"Connect" action:@selector(connectTapped:)];
    self.disconnectButton = [self buttonWithTitle:@"Disconnect" action:@selector(disconnectTapped:)];

    self.deviceMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.deviceMenu.translatesAutoresizingMaskIntoConstraints = NO;
    [self.deviceMenu.widthAnchor constraintGreaterThanOrEqualToConstant:360].active = YES;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        self.scanButton,
        self.deviceMenu,
        self.connectButton,
        self.disconnectButton,
    ]];
    [self configureStack:stack];
    return stack;
}

- (NSStackView *)buildGattControls {
    self.pairCodeField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.pairCodeField.stringValue = @"135790";
    self.pairCodeField.placeholderString = @"Pair code";
    self.pairCodeField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pairCodeField.widthAnchor constraintGreaterThanOrEqualToConstant:90].active = YES;

    self.payloadField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.payloadField.stringValue = @"hello from Objective-C macOS";
    self.payloadField.placeholderString = @"Echo, command, or rule:quiet";
    self.payloadField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.payloadField.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;

    self.pairButton = [self buttonWithTitle:@"Pair" action:@selector(pairTapped:)];
    self.pingButton = [self buttonWithTitle:@"Ping" action:@selector(pingTapped:)];
    self.infoButton = [self buttonWithTitle:@"Info" action:@selector(infoTapped:)];
    self.writeButton = [self buttonWithTitle:@"Echo" action:@selector(writeTapped:)];
    self.telemetryButton = [self buttonWithTitle:@"Telemetry" action:@selector(telemetryTapped:)];
    self.commandButton = [self buttonWithTitle:@"Command" action:@selector(commandTapped:)];
    self.rawButton = [self buttonWithTitle:@"Raw" action:@selector(rawTapped:)];
    self.readButton = [self buttonWithTitle:@"Read" action:@selector(readTapped:)];
    self.notifyButton = [self buttonWithTitle:@"Notify On" action:@selector(notifyTapped:)];

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        self.pairCodeField,
        self.pairButton,
        self.pingButton,
        self.infoButton,
        self.payloadField,
        self.writeButton,
        self.telemetryButton,
        self.commandButton,
        self.rawButton,
        self.readButton,
        self.notifyButton,
    ]];
    [self configureStack:stack];
    return stack;
}

- (NSStackView *)buildRuleControls {
    self.ruleModeLabel = [self labelWithText:@"Rule mode: normal"];
    self.ruleModeLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.ruleModeControl = [NSSegmentedControl segmentedControlWithLabels:@[ @"Normal", @"Quiet", @"Burst" ]
                                                              trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                    target:self
                                                                    action:@selector(ruleModeChanged:)];
    self.ruleModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *stack = [NSStackView stackViewWithViews:@[
        self.ruleModeLabel,
        self.ruleModeControl,
    ]];
    [self configureStack:stack];
    return stack;
}

- (NSScrollView *)buildLogView {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.borderType = NSBezelBorder;
    scrollView.hasVerticalScroller = YES;

    self.logTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.logTextView.editable = NO;
    self.logTextView.selectable = YES;
    self.logTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.logTextView.textColor = NSColor.blackColor;
    self.logTextView.backgroundColor = NSColor.whiteColor;
    self.logTextView.verticallyResizable = YES;
    self.logTextView.horizontallyResizable = NO;
    self.logTextView.textContainerInset = NSMakeSize(6, 6);
    self.logTextView.textContainer.widthTracksTextView = YES;
    scrollView.documentView = self.logTextView;
    return scrollView;
}

- (void)configureStack:(NSStackView *)stack {
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
}

- (NSTextField *)labelWithText:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

#pragma mark - Actions

- (void)scanTapped:(id)sender {
    if (self.centralController.isScanning) {
        [self.centralController stopScan];
    } else {
        [self.centralController startScan];
    }
}

- (void)connectTapped:(id)sender {
    NSInteger index = self.deviceMenu.indexOfSelectedItem;
    if (index >= 0) {
        [self.centralController connectDeviceAtIndex:(NSUInteger)index];
    }
}

- (void)disconnectTapped:(id)sender {
    [self.centralController disconnect];
}

- (void)writeTapped:(id)sender {
    [self.centralController writeText:self.payloadField.stringValue];
}

- (void)pairTapped:(id)sender {
    [self.centralController sendPairCode:self.pairCodeField.stringValue];
}

- (void)pingTapped:(id)sender {
    [self.centralController sendProtocolPing];
}

- (void)infoTapped:(id)sender {
    [self.centralController sendProtocolGetInfo];
}

- (void)telemetryTapped:(id)sender {
    [self.centralController sendTelemetryRequest];
}

- (void)commandTapped:(id)sender {
    NSString *name = self.payloadField.stringValue.length > 0 ? self.payloadField.stringValue : @"identify";
    NSString *ruleMode = [self eventRuleModeFromCommandText:name];
    if (ruleMode.length > 0) {
        [self.centralController sendEventRuleMode:ruleMode];
        return;
    }
    [self.centralController sendCommandNamed:name];
}

- (void)ruleModeChanged:(NSSegmentedControl *)sender {
    NSArray<NSString *> *modes = @[ @"normal", @"quiet", @"burst" ];
    NSInteger selectedSegment = sender.selectedSegment;
    if (selectedSegment < 0 || selectedSegment >= (NSInteger)modes.count) {
        return;
    }
    [self.centralController sendEventRuleMode:modes[(NSUInteger)selectedSegment]];
}

- (void)rawTapped:(id)sender {
    [self.centralController sendRawText:self.payloadField.stringValue];
}

- (void)readTapped:(id)sender {
    [self.centralController readValue];
}

- (void)notifyTapped:(id)sender {
    [self.centralController setNotifyEnabled:!self.centralController.isNotifyEnabled];
}

- (nullable NSString *)eventRuleModeFromCommandText:(NSString *)text {
    NSString *prefix = @"rule:";
    if (![text hasPrefix:prefix]) {
        return nil;
    }
    return [text substringFromIndex:prefix.length];
}

#pragma mark - UI state

- (void)refreshControls {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<NSString *> *labels = self.centralController.discoveredDeviceLabels;
        NSInteger selectedIndex = self.deviceMenu.indexOfSelectedItem;
        [self.deviceMenu removeAllItems];
        if (labels.count == 0) {
            [self.deviceMenu addItemWithTitle:@"No peripherals discovered"];
        } else {
            [self.deviceMenu addItemsWithTitles:labels];
            if (selectedIndex >= 0 && selectedIndex < (NSInteger)labels.count) {
                [self.deviceMenu selectItemAtIndex:selectedIndex];
            }
        }

        self.scanButton.title = self.centralController.isScanning ? @"Stop Scan" : @"Scan";
        self.connectButton.enabled = labels.count > 0 && !self.centralController.isConnected;
        self.disconnectButton.enabled = self.centralController.isConnected;
        self.pairButton.enabled = self.centralController.isCharacteristicReady;
        self.pingButton.enabled = self.centralController.isCharacteristicReady;
        self.infoButton.enabled = self.centralController.isCharacteristicReady;
        self.readButton.enabled = self.centralController.isCharacteristicReady;
        self.writeButton.enabled = self.centralController.isCharacteristicReady;
        self.telemetryButton.enabled = self.centralController.isCharacteristicReady;
        self.commandButton.enabled = self.centralController.isCharacteristicReady;
        self.ruleModeLabel.stringValue = [NSString stringWithFormat:@"Rule mode: %@", self.centralController.eventRuleMode];
        self.ruleModeControl.enabled = self.centralController.isCharacteristicReady;
        self.ruleModeControl.selectedSegment = [self selectedRuleModeSegment];
        self.rawButton.enabled = self.centralController.isCharacteristicReady;
        self.notifyButton.enabled = self.centralController.isCharacteristicReady;
        self.notifyButton.title = self.centralController.isNotifyEnabled ? @"Notify Off" : @"Notify On";
    });
}

- (NSInteger)selectedRuleModeSegment {
    if ([self.centralController.eventRuleMode isEqualToString:@"quiet"]) {
        return 1;
    }
    if ([self.centralController.eventRuleMode isEqualToString:@"burst"]) {
        return 2;
    }
    return 0;
}

- (void)appendLog:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.logTextView) {
            return;
        }
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:NSDate.date], message];

        NSDictionary *attributes = @{
            NSFontAttributeName: self.logTextView.font ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: NSColor.blackColor,
        };
        NSAttributedString *chunk = [[NSAttributedString alloc] initWithString:line attributes:attributes];
        [self.logTextView.textStorage appendAttributedString:chunk];

        NSUInteger length = self.logTextView.textStorage.length;
        if (length > 0) {
            [self.logTextView scrollRangeToVisible:NSMakeRange(length - 1, 1)];
        }
    });
}

@end
