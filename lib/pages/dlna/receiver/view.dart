import 'package:PiliPlus/services/nva_receiver/nva_receiver_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NvaReceiverPage extends StatefulWidget {
  const NvaReceiverPage({super.key});

  @override
  State<NvaReceiverPage> createState() => _NvaReceiverPageState();
}

class _NvaReceiverPageState extends State<NvaReceiverPage> {
  NvaReceiverService get _service => Get.find<NvaReceiverService>();

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('DLNA 接收设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 开关
          Card(
            child: Obx(
              () => SwitchListTile(
                title: const Text('启用 DLNA 接收'),
                subtitle: Text(_service.isRunning.value ? '运行中' : '已停止'),
                value: _service.isRunning.value,
                onChanged: (v) {
                  if (v) {
                    _service.start();
                  } else {
                    _service.stop();
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 设备名称
          Card(
            child: Obx(
              () => ListTile(
                title: const Text('设备名称'),
                subtitle: Text(_service.deviceName.value),
                trailing: const Icon(Icons.edit),
                onTap: () => _editName(context),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 状态信息
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('服务状态', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Obx(
                    () => _StatusRow(
                      label: '运行状态',
                      value: _service.isRunning.value ? '运行中' : '已停止',
                      color: _service.isRunning.value
                          ? colorScheme.primary
                          : colorScheme.error,
                    ),
                  ),
                  const Divider(),
                  Obx(
                    () => _StatusRow(
                      label: '已连接设备',
                      value: '${_service.connectedClients.value}',
                    ),
                  ),
                  const Divider(),
                  const _StatusRow(
                    label: '端口 (TCP)',
                    value: '9958',
                  ),
                  const Divider(),
                  const _StatusRow(
                    label: '协议版本',
                    value: 'NVA/1.0 + DLNA',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 说明
          Card(
            color: colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('使用方法', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(
                    '1. 打开"启用 DLNA 接收"开关\n'
                    '2. 在同一局域网内的 B站客户端中选择投屏\n'
                    '3. 在设备列表中找到 "PiliPlus TV"\n'
                    '4. 选择视频并开始投屏\n\n'
                    '支持功能：\n'
                    '• 高清视频投屏\n'
                    '• 播放/暂停/停止\n'
                    '• 进度拖拽\n'
                    '• 清晰度切换\n'
                    '• 倍速播放\n'
                    '• 弹幕投屏',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editName(BuildContext context) {
    final controller = TextEditingController(text: _service.deviceName.value);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '输入设备名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _service.updateDeviceName(name);
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatusRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
