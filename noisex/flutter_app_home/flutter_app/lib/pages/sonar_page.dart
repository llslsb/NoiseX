import 'dart:math';

import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../models/constants.dart';
import '../widgets/pulse_button.dart';
import '../widgets/radar_animation.dart';

/// 发送弹窗占位示例轮换池（UI 评审 P2：每次打开换一句，
/// 消解"140 字里说什么"的空白焦虑；鸿蒙端 Index.ets 同池逐句对齐）。
const List<String> kSonarPlaceholderExamples = [
  '有人看过昨晚的极光新闻吗？',
  '此时此刻你在想什么？',
  '这座城市的深夜是什么样的？',
  '有什么话必须此刻说出口？',
  '今天最后一个想分享的念头？',
];


class SonarPage extends StatefulWidget {
  final Future<void> Function(String content) onSonarSent;
  final bool isListening;
  final Future<void> Function(bool value)? onToggleListening;
  final VoidCallback? onOpenProfile;
  final int cooldown;

  /// 冷却起始秒数，用于绘制 PulseButton 进度环。
  /// 默认与服务端 [Constants.sonarCooldownSeconds] 一致。
  final int cooldownTotal;
  final double statusBarHeight;

  /// 附近活跃用户数（P2-B 雷达 blip 真实化）。
  /// 0 表示尚未加载，UI 显示"正在探测附近信号..."。
  final int nearbyCount;

  /// false=尚未加载（探测中），true 后 0 人也如实显示（2026-10-31 决策：不造假数据）
  final bool nearbyLoaded;

  /// 雷达信号点数量，由后端 nearby-activity 接口 clamp 至 0..8。
  final int blipCount;

  const SonarPage({
    super.key,
    required this.onSonarSent,
    this.isListening = true,
    this.onToggleListening,
    this.onOpenProfile,
    this.cooldown = 0,
    this.cooldownTotal = Constants.sonarCooldownSeconds,
    this.statusBarHeight = 0,
    this.nearbyCount = 0,
    this.nearbyLoaded = false,
    this.blipCount = 0,
  });

  @override
  State<SonarPage> createState() => _SonarPageState();
}

class _SonarPageState extends State<SonarPage> {
  bool _showInput = false;
  bool _sending = false;
  String _sonar_content = '';
  int _placeholderIndex = 0;

  Future<void> _sendSonar() async {
    final content = _sonar_content;
    if (content.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await widget.onSonarSent(content);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    setState(() {
      _showInput = false;
      _sonar_content = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgBase,
      child: Padding(
        padding: EdgeInsets.only(top: widget.statusBarHeight),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.15,
                child: RadarAnimation(isActive: true, blipCount: widget.blipCount),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 顶部"设置"按钮（对齐鸿蒙端：橙字 + 10% 橙底 + 橙描边胶囊）
                    if (widget.onOpenProfile != null)
                      Align(
                        alignment: Alignment.topRight,
                        child: GestureDetector(
                          onTap: widget.onOpenProfile,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primaryInput,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.primaryBorder, width: 1),
                            ),
                            child: const Text(
                              '设置',
                              style: TextStyle(fontSize: 14, color: AppColors.primary),
                            ),
                          ),
                        ),
                      ),
                    const Text(
                      'NOISEX',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 3.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isListening ? '> 收听模式已开启' : '> 静默模式',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (!_showInput)
                      GestureDetector(
                        // 对齐鸿蒙端 PulseButton 语义：点按展开输入框，
                        // 发送必须携带文字（服务端 content @NotBlank，
                        // 旧版"短按瞬发空声呐"必然 400，联调缺陷 B8）
                        onTap: () {
                          setState(() {
                            _showInput = true;
                            // UI 评审 P2：每次打开轮换一条占位示例
                            _placeholderIndex =
                                Random().nextInt(kSonarPlaceholderExamples.length);
                          });
                        },
                        onLongPress: () {
                          setState(() {
                            _showInput = true;
                            _placeholderIndex =
                                Random().nextInt(kSonarPlaceholderExamples.length);
                          });
                        },
                        child: PulseButton(
                          cooldown: widget.cooldown,
                          cooldownTotal: widget.cooldownTotal,
                          isActive: true,
                          onPulse: () {
                            setState(() {
                              _showInput = true;
                              _placeholderIndex =
                                  Random().nextInt(kSonarPlaceholderExamples.length);
                            });
                          },
                        ),
                      )
                    else
                      _buildInputModal(),
                    // UI 评审 P0：冷却态补原因说明（此前只有裸秒数，
                    // 用户不知道冷却保护的是什么；鸿蒙端同款文案）
                    if (widget.cooldown > 0) ...[
                      const SizedBox(height: 12),
                      Opacity(
                        opacity: 0.6,
                        child: Text(
                          '冷却保护：每小时 3 次上限，防止刷屏',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard.withOpacity(0.5),
                        border: Border.all(color: AppColors.primaryBorder),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '收听模式',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 12),
                          Switch(
                            value: widget.isListening,
                            onChanged: widget.onToggleListening,
                            // 对齐鸿蒙端 Toggle：选中轨道 primary、滑块白色
                            activeColor: Colors.white,
                            activeTrackColor: AppColors.primary,
                            inactiveThumbColor: Colors.white,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 附近活跃人数（雷达 blip 真实化，P2-B）
                    // 对齐鸿蒙端：12px textSecondary + 0.7 透明度（UI 评审 §13：提示类 ≥12px）
                    Opacity(
                      opacity: 0.7,
                      child: Text(
                        // 四态：静默 / 探测中 / 0 人如实显示 / 正常计数。
                        // 静默模式不取定位、不轮询人数，明说「不接收、不计入」，
                        // 免得旧数字或「探测中」误导（2026-11-06）
                        !widget.isListening
                            ? '静默中：不接收脉冲，也不计入附近人数'
                            : !widget.nearbyLoaded
                                ? '正在探测附近信号...'
                                : widget.nearbyCount > 0
                                    ? '附近约 ${widget.nearbyCount} 人活跃'
                                    : '附近 0 人活跃',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 280,
                      child: Column(
                        children: [
                          // UI 评审 §1-5：与按钮文案语义重复的引导语替换为
                          // 一条产品哲学文案（鸿蒙端同步）
                          const Text(
                            '每一次脉冲，只送给此刻在线的人',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          // 对齐鸿蒙端：说明文案 12px textSecondary + 0.6 透明度
                          Opacity(
                            opacity: 0.6,
                            child: Text(
                              '匹配基于地理位置和时间，无算法干预',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputModal() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border.all(color: const Color(0x66FF6B35), width: 2),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 40,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '> 发出声呐信号',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            maxLength: Constants.sonarMaxLength,
            maxLines: 4,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: kSonarPlaceholderExamples[_placeholderIndex],
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              // UI 评审 P0（T5 实锤）：关闭 maxLength 自带计数器，
              // 只保留下方手写计数器——此前弹窗渲染了两枚重复的 0/140
              counterText: '',
              filled: true,
              fillColor: AppColors.bgBase,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.primaryBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.primaryBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) => setState(() => _sonar_content = value),
          ),
          const SizedBox(height: 16),
          // 对齐鸿蒙端：计数器在左、按钮在右，同一行
          Row(
            children: [
              Text(
                '${_sonar_content.length}/${Constants.sonarMaxLength}',
                style: TextStyle(
                  fontSize: 12,
                  // UI 评审 P1：接近上限变色预警（≤120 灰 / 121-139 橙 / 140 红）
                  color: _sonar_content.length >= Constants.sonarMaxLength
                      ? AppColors.error
                      : _sonar_content.length >= Constants.sonarMaxLength - 20
                          ? AppColors.primary
                          : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => setState(() {
                  _showInput = false;
                  _sonar_content = '';
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bgMuted,
                  foregroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: !_sending &&
                        _sonar_content.isNotEmpty &&
                        _sonar_content.length <= Constants.sonarMaxLength
                    ? _sendSonar
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.bgBase,
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                child: Text(_sending ? '发送中...' : '发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
