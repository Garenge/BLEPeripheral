#import "ViewController.h"

@interface ViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) BLECentralController *centralController;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UITextField *echoTextField;
@property (nonatomic, strong) UILabel *statusLabel;

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
    [self buildUI];
    __weak typeof(self) weakSelf = self;
    self.centralController.discoveryHandler = ^{
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
        [self makeButton:@"Ping" action:@selector(pingTapped)],
        [self makeButton:@"Info" action:@selector(infoTapped)],
        [self makeButton:@"Echo" action:@selector(echoTapped)],
    ]];

    UIStackView *dataButtons = [self buttonRow:@[
        [self makeButton:@"Read" action:@selector(readTapped)],
        [self makeButton:@"Notify On" action:@selector(notifyOnTapped)],
        [self makeButton:@"Notify Off" action:@selector(notifyOffTapped)],
    ]];

    self.echoTextField = [[UITextField alloc] init];
    self.echoTextField.placeholder = @"Echo text";
    self.echoTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.echoTextField.text = @"Hello from iPhone";
    self.echoTextField.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *legacyButton = [self makeButton:@"Legacy Write" action:@selector(legacyTapped)];
    legacyButton.translatesAutoresizingMaskIntoConstraints = NO;

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
        protocolButtons,
        self.echoTextField,
        dataButtons,
        legacyButton,
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
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)refreshStatus {
    self.statusLabel.text = [NSString stringWithFormat:@"Scan=%@ Connect=%@ Notify=%@ | Tap device to connect",
                              self.centralController.isScanning ? @"YES" : @"NO",
                              self.centralController.isConnected ? @"YES" : @"NO",
                              self.centralController.isNotifying ? @"YES" : @"NO"];
    [self.tableView reloadData];
}

- (void)appendLogLine:(NSString *)line {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logTextView.text = [self.logTextView.text stringByAppendingString:line];
        NSRange end = NSMakeRange(self.logTextView.text.length, 0);
        [self.logTextView scrollRangeToVisible:end];
    });
    [self refreshStatus];
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

- (void)infoTapped {
    [self.centralController sendProtocolGetInfo];
}

- (void)echoTapped {
    [self.centralController sendProtocolEcho:self.echoTextField.text];
}

- (void)legacyTapped {
    [self.centralController sendLegacyText:self.echoTextField.text];
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

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.centralController.discoveredPeripherals.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DeviceCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DeviceCell"];
    }
    CBPeripheral *peripheral = self.centralController.discoveredPeripherals[indexPath.row];
    cell.textLabel.text = peripheral.name ?: @"Unnamed";
    cell.detailTextLabel.text = peripheral.identifier.UUIDString;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CBPeripheral *peripheral = self.centralController.discoveredPeripherals[indexPath.row];
    [self.centralController connectPeripheral:peripheral];
    [self refreshStatus];
}

@end
