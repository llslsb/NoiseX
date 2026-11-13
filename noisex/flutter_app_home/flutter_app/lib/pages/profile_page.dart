import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../services/ritual_animation_service.dart';
import '../widgets/harmony_feedback.dart';

/// 设置页（对齐鸿蒙端 ProfilePage.ets + BlockedListPage.ets）。
///
/// 结构与交互逐项对齐原生第一版：
/// - 头部「← 设置」，无头像、无隐私仪表盘（Flutter 单端发明已移除）
/// - 三个资料字段：显示态点值进入编辑；编辑态仅「保存」按钮（原生无取消）
/// - 「其他」区：仪式动效开关 / 拉黑列表（灰描边）/ 重置身份（红描边）
/// - 「拉黑列表」子页与解除确认弹窗逐字对齐 BlockedListPage
class ProfilePage extends StatefulWidget {
  final VoidCallback onBack;
  final Future<void> Function() onResetIdentity;

  const ProfilePage({
    super.key,
    required this.onBack,
    required this.onResetIdentity,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isEditing = false;
  bool _isSaving = false;
  bool _animEnabled = true;

  // 显示态数据（保存成功后回写）
  String _signature = '';
  String _city = '';
  String _contact = '';
  // 编辑态输入（对应原生 inputSignature/inputCity/inputContact）
  final _inputSignature = TextEditingController();
  final _inputCity = TextEditingController();
  final _inputContact = TextEditingController();

  // 拉黑列表子页状态（对齐 BlockedListPage）
  bool _showBlockedList = false;
  bool _loadingBlocks = false;
  List<String> _blockedUsers = [];

  // 通知授权状态（granted/refused/unknown；OHOS 拒绝后给设置页引导）
  String _notificationAuth = 'unknown';

  @override
  void initState() {
    super.initState();
    _animEnabled = RitualAnimationService.instance.ritualAnimationEnabled;
    _loadProfile();
    _loadNotificationAuth();
  }

  @override
  void dispose() {
    _inputSignature.dispose();
    _inputCity.dispose();
    _inputContact.dispose();
    super.dispose();
  }

  Future<void> _loadNotificationAuth() async {
    final state = await PushService().notificationAuthState();
    if (!mounted) return;
    setState(() => _notificationAuth = state);
  }

  /// 推送修复根因③ UI：通知授权被拒（1600004）后系统授权框不再弹，
  /// 唯一开启路径是设置页跳系统通知设置（OHOS 半模态，关闭时带回结果）
  Future<void> _openNotificationSettings() async {
    final granted = await PushService().openNotificationSettingsAndRefresh();
    if (!mounted) return;
    final state = granted ? 'granted' : 'refused';
    setState(() => _notificationAuth = state);
    if (granted) {
      unawaited(showHarmonyToast(context, '通知已开启'));
    }
  }

  Future<void> _loadProfile() async {
    final result = await ApiService().getProfile();
    if (!mounted) return;
    if (result.isSuccess && result.data != null) {
      setState(() {
        _signature = result.data!.signature;
        _city = result.data!.city;
        _contact = result.data!.contact;
        _inputSignature.text = _signature;
        _inputCity.text = _city;
        _inputContact.text = _contact;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final result = await ApiService().updateProfile(
        signature: _inputSignature.text,
        city: _inputCity.text,
        contact: _inputContact.text,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        // 对齐原生：保存成功静默回到显示态（无成功 toast）
        setState(() {
          _signature = _inputSignature.text;
          _city = _inputCity.text;
          _contact = _inputContact.text;
          _isEditing = false;
        });
      } else {
        unawaited(showHarmonyToast(
            context, result.message.isNotEmpty ? result.message : '保存失败'));
      }
    } catch (_) {
      if (!mounted) return;
      unawaited(showHarmonyToast(context, '保存失败'));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _showBlockedList = true;
      _loadingBlocks = true;
    });
    final result = await ApiService().getBlockedList();
    if (!mounted) return;
    setState(() {
      _loadingBlocks = false;
      _blockedUsers = result.data ?? [];
    });
    if (!result.isSuccess) {
      unawaited(showHarmonyToast(
          context, result.message.isNotEmpty ? result.message : '拉黑列表加载失败'));
    }
  }

  /// 对齐原生 maskUserId：前 4 位 + '*' 补齐 + 后 4 位
  String _maskUserId(String userId) {
    if (userId.length <= 8) return userId;
    final prefix = userId.substring(0, 4);
    final suffix = userId.substring(userId.length - 4);
    final mask = '*' * (userId.length - 8);
    return '$prefix$mask$suffix';
  }

  @override
  Widget build(BuildContext context) {
    // Material 包裹：本页由 app.dart 状态分支渲染、无 Scaffold 祖先，
    // 缺 Material 会触发 TextField 黄色下划线与 Switch 渲染报错
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: AppColors.bgBase,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(_showBlockedList ? '拉黑列表' : '设置'),
              Expanded(
                child: _showBlockedList ? _buildBlockedList() : _buildProfile(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 头部（对齐原生 HeaderBuilder：← 36×36 透明按钮 + 标题 18 加粗）
  Widget _buildHeader(String title) {
    return Row(
      children: [
        InkWell(
          onTap: _showBlockedList
              ? () => setState(() => _showBlockedList = false)
              : widget.onBack,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: const Text('←',
                style:
                    TextStyle(fontSize: 20, color: AppColors.textPrimary)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
        ),
      ],
    ).padding(const EdgeInsets.symmetric(horizontal: 12, vertical: 10));
  }

  Widget _buildProfile() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldSection('一句签名', _signature, _inputSignature,
              placeholder: '比如：夜跑爱好者 / 只聊天文',
              emptyHint: '填一句签名，对方解锁资料后第一眼看到'),
          _buildFieldSection('城市', _city, _inputCity,
              placeholder: '比如：芜湖',
              emptyHint: '填了城市，匹配的陌生人更有共同话题'),
          _buildFieldSection('一个公开联系方式', _contact, _inputContact,
              placeholder: '比如：一个邮箱或公开账号',
              emptyHint: '保存连接后对方靠它联系你'),
          // 对齐原生：12px textSecondary 0.6 透明度，padding 16
          const Opacity(
            opacity: 0.6,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('资料卡仅在双方确认深度交流并解锁后对对方可见',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
          ),
          if (_isEditing) _buildSaveButton(),
          // 分隔区域「其他」
          const Opacity(
            opacity: 0.6,
            child: Padding(
              padding: EdgeInsets.only(top: 32, bottom: 8, left: 16, right: 16),
              child: Text('其他',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
          ),
          _buildRitualToggle(),
          // 通知授权引导行：仅授权态非 granted 时出现（OHOS 1600004 拒绝后引导）
          if (_notificationAuth != 'granted') ...[
            const SizedBox(height: 8),
            _buildOutlinedButton(
              _notificationAuth == 'refused' ? '开启通知提醒' : '通知授权',
              AppColors.textSecondary,
              AppColors.divider,
              _openNotificationSettings,
            ),
          ],
          _buildOutlinedButton(
            '拉黑列表',
            AppColors.textSecondary,
            AppColors.divider,
            _loadBlockedUsers,
          ),
          const SizedBox(height: 8),
          _buildOutlinedButton(
            '重置身份',
            const Color(0xFFE84855),
            const Color(0xFFE84855),
            _confirmResetIdentity,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 资料字段（对齐原生：label 12 textSecondary；显示值 16px 白/未设置灰，
  /// 点值进入编辑；编辑态 TextInput 40 高 bg_base 底 primary_border 描边）
  /// UI 评审 P1（§7-1）：显示态"未设置"下加动机行——填了对方解锁后能看到。
  Widget _buildFieldSection(String label, String value,
      TextEditingController controller,
      {required String placeholder, String? emptyHint}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          if (_isEditing)
            SizedBox(
              height: 40,
              child: TextField(
                controller: controller,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle:
                      const TextStyle(color: AppColors.textSecondary),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: AppColors.bgBase,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide:
                        const BorderSide(color: AppColors.primaryBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide:
                        const BorderSide(color: AppColors.primaryBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
            )
          else
            // 对齐原生：点击值进入编辑模式（无独立「编辑」入口）
            GestureDetector(
              onTap: () => setState(() => _isEditing = true),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value.isNotEmpty ? value : '未设置',
                      style: TextStyle(
                        fontSize: 16,
                        color: value.isNotEmpty ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                    if (value.isEmpty && emptyHint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        emptyHint,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 保存按钮（对齐原生：80% 宽 × 44 高、16px 白字、primary 底，无取消按钮）
  Widget _buildSaveButton() {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.8,
        child: Container(
          height: 44,
          margin: const EdgeInsets.only(top: 24),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AppColors.primary.withOpacity(0.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
            child: Text(_isSaving ? '保存中...' : '保存',
                style:
                    const TextStyle(fontSize: 16, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  /// 仪式动效开关（对齐原生：80% 宽 × 40 高行，白钮橙轨 Switch）
  Widget _buildRitualToggle() {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.8,
        child: Container(
          height: 40,
          margin: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const Expanded(
                child: Text('仪式动效',
                    style: TextStyle(
                        fontSize: 14, color: AppColors.textPrimary)),
              ),
              Switch(
                value: _animEnabled,
                onChanged: (v) {
                  RitualAnimationService.instance.setRitualAnimationEnabled(v);
                  setState(() => _animEnabled = v);
                },
                // 对齐鸿蒙端 Toggle：选中轨道 primary、滑块白色
                activeColor: Colors.white,
                activeTrackColor: AppColors.primary,
                inactiveThumbColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 描边按钮（对齐原生：80% 宽 × 40 高、透明底、1px 描边 radius 4）
  Widget _buildOutlinedButton(
      String label, Color textColor, Color borderColor, VoidCallback onTap) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.8,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 14, color: textColor)),
          ),
        ),
      ),
    );
  }

  // ================= 拉黑列表子页（对齐 BlockedListPage.ets） =================

  Widget _buildBlockedList() {
    return Column(
      children: [
        Expanded(
          child: _loadingBlocks
              ? const Center(
                  child: Text('加载中...',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textSecondary)))
              : _blockedUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 对齐原生：🛡️ 64px + 0.2 透明度
                          Opacity(
                            opacity: 0.2,
                            child: Text('🛡️',
                                style: TextStyle(fontSize: 64)),
                          ),
                          const SizedBox(height: 16),
                          const Text('暂无拉黑用户',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 4),
                          // 对齐原生：12px textSecondary 0.6 透明度
                          const Opacity(
                            opacity: 0.6,
                            child: Text('在聊天页面点击"拉黑"后，对方会出现在这里',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      itemCount: _blockedUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _buildBlockedItem(_blockedUsers[index]),
                    ),
        ),
        // 底部提示（对齐原生：tab_bar_bg 底 + divider 顶线）
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: AppColors.headerBarBg,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: const Text('解除拉黑后，对方仍可能通过声呐匹配到你',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  /// 拉黑条目（对齐原生：🚫 20 + 标题 15 + 掩码 ID 12；解除按钮 primary 描边 radius 8）
  Widget _buildBlockedItem(String userId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Text('🚫', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已拉黑用户',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Opacity(
                  opacity: 0.7,
                  child: Text(_maskUserId(userId),
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _confirmUnblock(userId),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primaryBorder, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('解除',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.primary)),
            ),
          ),
        ],
      ),
    );
  }

  /// 解除拉黑确认弹窗（逐字对齐原生 bindContentCover 弹窗）
  Future<void> _confirmUnblock(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🚫', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text('解除拉黑',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('确定要解除拉黑吗？',
                style: TextStyle(
                    fontSize: 15, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Opacity(
              opacity: 0.8,
              child: Text('解除后对方仍可能通过声呐匹配到你',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.bgCard,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('取消',
                          style: TextStyle(fontSize: 15)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.bgBase,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('确定解除',
                          style: TextStyle(fontSize: 15)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final result = await ApiService().unblockUser(userId);
    if (!mounted) return;
    if (result.isSuccess) {
      setState(() =>
          _blockedUsers = _blockedUsers.where((id) => id != userId).toList());
    } else {
      unawaited(showHarmonyToast(context,
          result.message.isNotEmpty ? result.message : '解除拉黑失败'));
    }
  }

  /// 重置身份确认弹窗（损失清单逐字对齐原生 showResetConfirmDialog）。
  /// UI 评审 P0（§7-2）：全应用最不可逆操作，确认方式从"点一下"升级为
  /// "按住 3 秒"——误触不可能完成，鸿蒙端 ProfilePage.ets 同款交互。
  Future<void> _confirmResetIdentity() async {
    final confirmed = await showHarmonyHoldConfirmDialog(
      context,
      title: '重置身份',
      message: '此操作不可撤销！重置后：\n\n'
          '1. 当前身份的所有数据将被永久删除\n'
          '2. 所有进行中的对话将被关闭\n'
          '3. 对方将收到对话关闭通知\n'
          '4. 你将以全新身份重新开始',
      holdText: '按住 3 秒确认重置',
      holdSeconds: 3,
    );
    if (confirmed) {
      await widget.onResetIdentity();
    }
  }
}

extension _PaddingX on Widget {
  Widget padding(EdgeInsets insets) => Padding(padding: insets, child: this);
}
