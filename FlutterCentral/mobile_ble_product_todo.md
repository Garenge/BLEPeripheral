# Mobile BLE Product Todo

本文记录 FlutterCentral 后续移动端产品化待办。当前优先级以 Android/iOS 真机联调和移动端体验为主，macOS Central 客户端作为辅助验证端。

## 1. Android/iOS BLE 联调

- [x] 生成 Android/iOS 平台工程并完成基础构建验证。
- [x] 配置 Android BLE 权限、iOS 蓝牙权限和 macOS 蓝牙沙盒权限。
- [ ] 使用 Android 真机和 iPhone 真机同时验证 BLE 扫描。
- [ ] 确认 Android 和 iOS 都能扫描到 `MacBLE-Demo` 广播。
- [ ] 确认 Android 和 iOS 都能连接目标外设并发现 Service `FFF0`。
- [ ] 确认 Android 和 iOS 都能发现 Characteristic `FFF1`。
- [ ] 确认 Android 和 iOS 都能开启 Notify。
- [ ] 确认 Android 和 iOS 都能发送 Pair code `135790` 并捕获 session token。
- [ ] 确认 Android 和 iOS 都能执行 `getInfo`、`ping`、`echo`、`telemetry`、`command`。
- [ ] 确认 Android 和 iOS 都能处理 raw echo：写入非协议 payload，接收 `00 AA` + 原始 payload。
- [ ] 确认 Android 和 iOS 都能处理 oversized Notify chunk 重组。
- [ ] 记录 Android/iOS 的差异，包括权限弹窗、扫描耗时、remoteId 表现、MTU 和断连恢复。

## 2. 移动端 UI 适配

- [x] 将移动端作为默认体验重新设计，macOS 宽屏布局作为次要适配。
- [x] 修复当前移动端 UI 挤压问题。
- [x] 修复底部日志在移动端无法正常显示的问题。
- [x] 将扫描列表、连接状态、操作按钮、日志拆成更适合手机的分区或 Tab。
- [x] 将高频操作做成清晰的主流程：扫描、连接、配对、能力发现、数据传输。
- [x] 将低频调试操作折叠到高级/调试区域。
- [x] 优化按钮布局，避免移动端 Wrap 过长导致主要内容被挤出。
- [x] 优化日志展示，支持全屏查看、清空、复制关键日志。
- [x] 增加连接状态、权限状态、错误提示和空状态。
- [ ] 在 Android/iOS 真机尺寸上验证无溢出、无重叠、日志可读。

## 3. 蓝牙协议规范文档

- [x] 从 `../MacPeripheralOC` 提取外设实现细节。
- [x] 明确 Peripheral 名称、Service UUID、Characteristic UUID。
- [x] 明确 Characteristic 支持的属性：read、write、notify。
- [x] 明确 Pair 流程、Pair code、session token 规则。
- [x] 明确 JSON envelope 字段：`v`、`op`、`id`、`token`、`body`、`ok`、`err`。
- [x] 明确支持的 operation：`pair`、`getInfo`、`ping`、`echo`、`telemetry`、`command`、`chunk`。
- [x] 明确 command 指令：`identify`、`sample`、`resetCounters`、`setEventRule`。
- [x] 明确 event rule：`normal`、`quiet`、`burst`。
- [x] 明确 raw legacy echo 规则：返回 `00 AA` + 原始 payload。
- [x] 明确 oversized Notify chunk 规则、大小限制和重组策略。
- [x] 输出规范文档，建议文件名：`ble_protocol_spec.md`。
- [x] 在 README 中加入规范文档入口。

## 4. 按协议文档产品化移动端

- [x] 以 `ble_protocol_spec.md` 为唯一协议依据，反向校准 Flutter 端实现。
- [x] 将移动端功能从“调试面板”改造成“产品流程”。
- [x] 首屏突出扫描和连接状态。
- [x] 连接成功后展示设备能力、配对状态、事件规则、最近遥测。
- [x] 数据传输区提供 Echo、Telemetry、Command 和 Raw 的清晰入口。
- [x] 对 Pair、Info、Ping、Echo、Telemetry、Command 建立统一的请求状态和错误展示。
- [x] 将协议日志与用户可见结果分层展示，避免普通用户直接面对大量原始 JSON。
- [x] 保留高级调试日志，方便 Android/iOS/macOS 对照排障。
- [x] 为关键流程补充 widget/controller 测试。
- [ ] 用 Android 真机、iPhone 真机、macOS 端完成一轮端到端验收。
