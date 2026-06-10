#import "ViewController.h"

static NSUInteger const kMaxLogLineCount = 300;

@interface ViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) BLECentralController *centralController;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UITextField *echoTextField;
@property (nonatomic, strong) UITextField *pairCodeField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISegmentedControl *ruleModeControl;
@property (nonatomic, strong) UIButton *demoFlowButton;
@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;

@end

@implementation ViewController

- (instancetype)initWithCentralController:(BLECentralController *)centralController {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _centralController = centralController;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"BLE Central";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.logLines = [NSMutableArray array];
    [self buildUI];
    __weak typeof(self) weakSelf = self;
    self.centralController.discoveryHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf refreshStatus];
        });
    };
    self.centralController.stateHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf refreshStatus];
        });
    };
    [self refreshStatus];
}

- (void)buildUI {
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *topButtons = [self buttonRow:@[
        [self makeButton:@"Scan" action:@selector(scanTapped)],
        [self makeButton:@"Stop" action:@selector(stopScanTapped)],
        [self makeButton:@"Disconnect" action:@selector(disconnectTapped)],
    ]];

    UIStackView *protocolButtons = [self buttonRow:@[
        [self makeButton:@"Pair" action:@selector(pairTapped)],
        [self makeButton:@"Ping" action:@selector(pingTapped)],
        [self makeButton:@"Info" action:@selector(infoTapped)],
        [self makeButton:@"Echo" action:@selector(echoTapped)],
    ]];

    UIStackView *advancedButtons = [self buttonRow:@[
        [self makeButton:@"Telemetry" action:@selector(telemetryTapped)],
        [self makeButton:@"Command" action:@selector(commandTapped)],
        [self makeButton:@"Raw" action:@selector(legacyTapped)],
    ]];

    self.ruleModeControl = [[UISegmentedControl alloc] initWithItems:@[ @"Normal", @"Quiet", @"Burst" ]];
    self.ruleModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.ruleModeControl addTarget:self action:@selector(ruleModeChanged:) forControlEvents:UIControlEventValueChanged];
    self.demoFlowButton = [self makeButton:@"Run Demo" action:@selector(demoFlowTapped)];

    UIStackView *dataButtons = [self buttonRow:@[
        [self makeButton:@"Read" action:@selector(readTapped)],
        [self makeButton:@"Notify On" action:@selector(notifyOnTapped)],
        [self makeButton:@"Notify Off" action:@selector(notifyOffTapped)],
        self.demoFlowButton,
    ]];

    UIStackView *logButtons = [self buttonRow:@[
        [self makeButton:@"Clear Logs" action:@selector(clearLogsTapped)],
    ]];

    self.pairCodeField = [[UITextField alloc] init];
    self.pairCodeField.placeholder = @"Pair code";
    self.pairCodeField.borderStyle = UITextBorderStyleRoundedRect;
    self.pairCodeField.text = @"135790";
    self.pairCodeField.keyboardType = UIKeyboardTypeNumberPad;
    self.pairCodeField.translatesAutoresizingMaskIntoConstraints = NO;

    self.echoTextField = [[UITextField alloc] init];
    self.echoTextField.placeholder = @"Echo, command, or rule:quiet";
    self.echoTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.echoTextField.text = @"Hello from iPhone";
    self.echoTextField.translatesAutoresizingMaskIntoConstraints = NO;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;

    self.logTextView = [[UITextView alloc] init];
    self.logTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logTextView.editable = NO;
    self.logTextView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.logTextView.backgroundColor = [UIColor secondarySystemBackgroundColor];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.statusLabel,
        topButtons,
        self.tableView,
        self.pairCodeField,
        protocolButtons,
        self.echoTextField,
        advancedButtons,
        self.ruleModeControl,
        dataButtons,
        logButtons,
        self.logTextView,
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:6 afterView:self.statusLabel];

    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [self.tableView.heightAnchor constraintEqualToConstant:140],
        [self.logTextView.heightAnchor constraintGreaterThanOrEqualToConstant:160],
    ]];
}

- (UIStackView *)buttonRow:(NSArray<UIButton *> *)buttons {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFillEqually;
    return row;
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.8;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)refreshStatus {
    self.statusLabel.text = [NSString stringWithFormat:@"Scan=%@ Connect=%@ Notify=%@ Rule=%@ | Tap device to connect",
                              self.centralController.isScanning ? @"YES" : @"NO",
                              self.centralController.isConnected ? @"YES" : @"NO",
                              self.centralController.isNotifying ? @"YES" : @"NO",
                              self.centralController.eventRuleMode];
    self.ruleModeControl.selectedSegmentIndex = [self selectedRuleModeSegment];
    self.ruleModeControl.enabled = self.centralController.isCharacteristicReady;
    self.demoFlowButton.enabled = self.centralController.isCharacteristicReady && !self.centralController.isDemoFlowRunning;
    NSString *demoTitle = self.centralController.isDemoFlowRunning ? @"Running Demo" : @"Run Demo";
    [self.demoFlowButton setTitle:demoTitle forState:UIControlStateNormal];
    [self.tableView reloadData];
}

- (void)appendLogLine:(NSString *)line {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logLines addObject:line];
        [self trimLogLinesIfNeeded];
        [self renderLogLines];
    });
    [self refreshStatus];
}

- (void)trimLogLinesIfNeeded {
    while (self.logLines.count > kMaxLogLineCount) {
        [self.logLines removeObjectAtIndex:0];
    }
}

- (void)renderLogLines {
    self.logTextView.text = [self.logLines componentsJoinedByString:@""];
    NSRange end = NSMakeRange(self.logTextView.text.length, 0);
    [self.logTextView scrollRangeToVisible:end];
}

#pragma mark - Actions

- (void)scanTapped {
    [self.centralController startScan];
    [self refreshStatus];
}

- (void)stopScanTapped {
    [self.centralController stopScan];
    [self refreshStatus];
}

- (void)disconnectTapped {
    [self.centralController disconnect];
    [self refreshStatus];
}

- (void)pingTapped {
    [self.centralController sendProtocolPing];
}

- (void)pairTapped {
    [self.centralController sendProtocolPairCode:self.pairCodeField.text];
}

- (void)infoTapped {
    [self.centralController sendProtocolGetInfo];
}

- (void)echoTapped {
    [self.centralController sendProtocolEcho:self.echoTextField.text];
}

- (void)legacyTapped {
    [self.centralController sendLegacyText:self.echoTextField.text];
}

- (void)telemetryTapped {
    [self.centralController sendProtocolTelemetry];
}

- (void)commandTapped {
    NSString *name = self.echoTextField.text.length > 0 ? self.echoTextField.text : @"identify";
    NSString *ruleMode = [self eventRuleModeFromCommandText:name];
    if (ruleMode.length > 0) {
        [self.centralController sendProtocolEventRuleMode:ruleMode];
        return;
    }
    [self.centralController sendProtocolCommand:name];
}

- (void)ruleModeChanged:(UISegmentedControl *)sender {
    NSArray<NSString *> *modes = @[ @"normal", @"quiet", @"burst" ];
    NSInteger selectedSegment = sender.selectedSegmentIndex;
    if (selectedSegment < 0 || selectedSegment >= (NSInteger)modes.count) {
        return;
    }
    [self.centralController sendProtocolEventRuleMode:modes[(NSUInteger)selectedSegment]];
}

- (void)readTapped {
    [self.centralController readCharacteristic];
}

- (void)notifyOnTapped {
    [self.centralController subscribeNotifications:YES];
}

- (void)notifyOffTapped {
    [self.centralController subscribeNotifications:NO];
}

- (void)demoFlowTapped {
    [self.centralController runDemoFlow];
}

- (void)clearLogsTapped {
    [self.logLines removeAllObjects];
    [self renderLogLines];
}

- (nullable NSString *)eventRuleModeFromCommandText:(NSString *)text {
    NSString *prefix = @"rule:";
    if (![text hasPrefix:prefix]) {
        return nil;
    }
    return [text substringFromIndex:prefix.length];
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

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.centralController.discoveredPeripherals.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DeviceCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DeviceCell"];
        cell.detailTextLabel.numberOfLines = 2;
    }
    CBPeripheral *peripheral = self.centralController.discoveredPeripherals[indexPath.row];
    cell.textLabel.text = peripheral.name ?: @"Unnamed";
    cell.detailTextLabel.text = [self.centralController detailForDiscoveredPeripheralAtIndex:(NSUInteger)indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CBPeripheral *peripheral = self.centralController.discoveredPeripherals[indexPath.row];
    [self.centralController connectPeripheral:peripheral];
    [self refreshStatus];
}

@end
