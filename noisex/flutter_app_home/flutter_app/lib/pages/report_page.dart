import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/api_service.dart';
import '../widgets/harmony_feedback.dart';

/// 举报页（结构与文案逐字对齐鸿蒙端 ReportPage.ets）：
/// - 表单态：举报对话 <signalCode> / 举报原因*（快捷 chips + 自由文本补充）/
///   手机号（选填，去恐惧化说明）/ 提交举报
/// - 完成态：举报已提交 / 已进入官方审核队列 / 举报编号 / 之后会发生什么
///
/// UI 评审 P0（§8）：
/// - 不再渲染内部 roomId（工程泄漏），只显示匿名信号码；
///   ArkTS 端 ReportPage.ets 同步改，上报 API 仍用 roomId（系统内部自会关联）
/// - 举报原因加 preset chips 降低门槛（点按填入，仍可自由编辑——后端
///   接口不变，无需三端联动）
/// - 手机号文案去恐惧化：保留"法律追溯"语义（与隐私协议承诺一致），
///   补充"不会透露给对方，不影响匿名身份"
/// - Material SnackBar → 鸿蒙深色 toast
class ReportPage extends StatefulWidget {
  final String roomId;

  /// 匿名信号码（RX-XXXX），仅用于界面展示。
  final String signalCode;
  final VoidCallback onBack;

  const ReportPage({
    super.key,
    required this.roomId,
    this.signalCode = '',
    required this.onBack,
  });

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _reasonController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _submitting = false;
  bool _isDone = false;
  String _reportId = '';

  /// 举报原因快捷项（UI 评审 P0 §8-3；鸿蒙端同款逐字对齐）
  static const List<String> _reasonPresets = [
    '骚扰辱骂',
    '色情低俗',
    '诈骗钓鱼',
    '违法违规',
    '其他',
  ];

  /// 鸿蒙端提交按钮硬编码红 #e74c3c（非 error token）
  static const Color _submitRed = Color(0xFFE74C3C);

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty || _submitting) return;
    setState(() => _submitting = true);

    try {
      final phoneNumber = _phoneController.text.trim();
      final result = await ApiService().reportRoom(
        widget.roomId,
        reason,
        phoneNumber: phoneNumber.isNotEmpty ? phoneNumber : null,
      );
      if (!mounted) return;
      setState(() {
        _reportId = result.data?.reportId ?? '';
        _isDone = true;
      });
    } catch (_) {
      if (!mounted) return;
      unawaited(showHarmonyToast(context, '举报提交失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: AppColors.bgBase,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  border:
                      Border(bottom: BorderSide(color: AppColors.primaryBorder)),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: widget.onBack,
                      child: const Icon(Icons.arrow_back,
                          color: AppColors.textPrimary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '举报',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isDone
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '举报已提交',
                              style: TextStyle(
                                  fontSize: 18, color: AppColors.primary),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '已进入官方审核队列',
                              style: TextStyle(
                                  fontSize: 14, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '举报编号：$_reportId',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                '接下来：官方将审核该对话；情况属实时对方账号会被限制使用，你的身份信息不会透露给对方。如需追踪请保留编号。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12,
                                    height: 1.6,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // UI 评审 P0：只显示匿名信号码，不暴露内部 roomId
                            Text(
                              '举报对话 ${widget.signalCode.isNotEmpty ? widget.signalCode : "与该陌生人"}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '举报原因 *',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            // 快捷原因 chips：点按填入文本框，可继续编辑补充
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _reasonPresets
                                  .map((preset) => _buildPresetChip(preset))
                                  .toList(),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _reasonController,
                              minLines: 4,
                              maxLines: 6,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: '请描述违规行为（可补充细节）...',
                                hintStyle:
                                    const TextStyle(color: AppColors.textMuted),
                                filled: true,
                                fillColor: AppColors.bgCard,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: const BorderSide(
                                      color: AppColors.primaryBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: const BorderSide(
                                      color: AppColors.primaryBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: const BorderSide(
                                      color: AppColors.primary),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              '手机号（选填，用于法律追溯）',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              maxLength: 11,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 14),
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: '选填，如 13800138000',
                                hintStyle: const TextStyle(
                                    color: AppColors.textMuted),
                                filled: true,
                                fillColor: AppColors.bgCard,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: const BorderSide(
                                      color: AppColors.primaryBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: const BorderSide(
                                      color: AppColors.primaryBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4),
                                  borderSide: const BorderSide(
                                      color: AppColors.primary),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // UI 评审 P0 §8-2：去恐惧化说明（语义与隐私协议
                            // "用于法律追溯、AES-256-GCM 加密"一致，不打架）
                            const Text(
                              '仅官方处理纠纷或法律追溯时依法使用，AES-256-GCM 加密存储；不会透露给对方，不影响匿名身份。',
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: SizedBox(
                                width: double.infinity,
                                child: FractionallySizedBox(
                                  widthFactor: 0.8,
                                  child: ElevatedButton(
                                    onPressed: _reasonController.text
                                            .trim()
                                            .isNotEmpty &&
                                            !_submitting
                                        ? _submit
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _submitRed,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          _submitRed.withOpacity(0.5),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      minimumSize: const Size(0, 44),
                                    ),
                                    child: Text(
                                      _submitting ? '提交中...' : '提交举报',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 快捷原因 chip：选中态橙底深字，未选中描边灰字；点按填入原因框。
  Widget _buildPresetChip(String preset) {
    final selected = _reasonController.text.trim() == preset;
    return GestureDetector(
      onTap: () {
        _reasonController.text = preset;
        _reasonController.selection = TextSelection.fromPosition(
          TextPosition(offset: _reasonController.text.length),
        );
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.primaryBorder,
          ),
        ),
        child: Text(
          preset,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.bgBase : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
