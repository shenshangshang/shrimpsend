import '../ui/product_scaffold.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../api/api.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../ui/app_ui.dart';
import '../utils/toast.dart';
import '../widgets/app_confirm_dialog.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  UserProfile? _profile;
  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!ref.read(authProvider).isLoggedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted)
      setState(() {
        _loading = true;
        _loadError = false;
      });
    try {
      final profile = await fetchUserProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logout() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppConfirmDialog.show(
      context,
      title: l10n.accountLogoutDialogTitle,
      content: l10n.accountLogoutDialogBody,
      confirmLabel: l10n.accountLogoutConfirm,
      isDanger: true,
      icon: LucideIcons.logOut,
    );
    if (!confirmed || !mounted) return;
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _deleteAccount() {
    showDialog(
      context: context,
      builder: (_) => _DeleteAccountDialog(email: _profile?.email ?? ''),
    );
  }

  void _changePassword() {
    showDialog(
      context: context,
      builder: (_) => _ChangePasswordDialog(email: _profile?.email ?? ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final loggedIn = ref.watch(authProvider).isLoggedIn;
    ref.listen(authProvider, (previous, next) {
      if (previous?.isLoggedIn != next.isLoggedIn && next.isLoggedIn)
        _loadProfile();
    });
    return ProductScaffold(
      settingsLocation: '/account',
      appBar: AppBar(title: Text(l10n.accountScreenTitle)),
      body: !loggedIn
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.userRound,
                      size: 38,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      zh ? '登录后管理账号与会员' : 'Sign in to manage your account',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      zh
                          ? '文件传输可以继续免登录使用。'
                          : 'You can keep transferring without an account.',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      child: Text(zh ? '登录' : 'Sign in'),
                    ),
                  ],
                ),
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(zh ? '暂时无法读取账号信息' : 'Unable to load your account'),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _loadProfile,
                    child: Text(zh ? '重试' : 'Retry'),
                  ),
                ],
              ),
            )
          : Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: ListView(
                  padding: const EdgeInsets.all(28),
                  children: [
                    Text(
                      zh
                          ? '账号用于管理会员。设备上的文件和会话独立保存。'
                          : 'Your account manages membership. Files and conversations stay on each device.',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textSecondary,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colors.accentSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            LucideIcons.userRound,
                            color: theme.colorScheme.primary,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _profile?.username ?? '',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _profile?.email ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Divider(),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      leading: const Icon(LucideIcons.lockKeyhole, size: 20),
                      title: Text(l10n.accountChangePassword),
                      subtitle: Text(
                        zh ? '更新用于账号登录的密码' : 'Update your sign-in password',
                      ),
                      trailing: const Icon(LucideIcons.chevronRight, size: 18),
                      onTap: _changePassword,
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      leading: const Icon(LucideIcons.badgeCheck, size: 20),
                      title: Text(zh ? '会员与名额' : 'Membership & slots'),
                      subtitle: Text(
                        zh
                            ? '查看套餐与已授权设备'
                            : 'Manage your plan and authorized devices',
                      ),
                      trailing: const Icon(LucideIcons.chevronRight, size: 18),
                      onTap: () =>
                          Navigator.pushNamed(context, '/settings/membership'),
                    ),
                    const Divider(),
                    const SizedBox(height: 28),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(LucideIcons.logOut, size: 16),
                        label: Text(l10n.accountLogout),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l10n.accountDeleteAccount,
                        style: TextStyle(fontSize: 14, color: colors.danger),
                      ),
                      subtitle: Text(
                        zh
                            ? '查看注销条件与影响'
                            : 'Review account deletion requirements',
                      ),
                      trailing: const Icon(LucideIcons.chevronRight, size: 18),
                      onTap: _deleteAccount,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  final String email;
  const _ChangePasswordDialog({required this.email});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _codeSending = false;
  bool _submitting = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldown = 60;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) {
          _cooldownTimer?.cancel();
          _cooldownTimer = null;
        }
      });
    });
  }

  Future<void> _sendCode() async {
    setState(() {
      _error = null;
      _codeSending = true;
    });
    try {
      await sendChangePasswordCode();
      if (!mounted) return;
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _codeSending = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(
          context,
        ).accountValidationEnterVerificationCode,
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await changePassword(code: code, newPassword: _newCtrl.text);
      if (!mounted) return;
      Navigator.pop(context);
      AppToast.show(
        context,
        message: AppLocalizations.of(context).accountPasswordChangedToast,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final codeEmpty = _codeCtrl.text.trim().isEmpty;
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final viewInsets = media.viewInsets;
    final dialogWidth = screenWidth <= AppSize.formMaxWidth + 32
        ? screenWidth - 32
        : AppSize.formMaxWidth;
    const verticalInset = 24.0;
    final maxDialogHeight =
        media.size.height -
        media.padding.top -
        media.padding.bottom -
        viewInsets.top -
        viewInsets.bottom -
        verticalInset * 2;

    return Dialog(
      insetPadding: EdgeInsets.only(
        left: AppDialog.insetPadding.left,
        right: AppDialog.insetPadding.right,
        top: verticalInset,
        bottom: verticalInset + viewInsets.bottom,
      ),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: maxDialogHeight > 0
              ? maxDialogHeight
              : media.size.height * 0.5,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.accountChangePasswordTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        foregroundColor: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.accountChangePasswordWarning,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  widget.email,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: colors.dangerSurface,
                      borderRadius: AppRadius.small,
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: colors.danger, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codeCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: InputDecoration(
                          labelText: l10n.accountLabelVerificationCode,
                          hintText: l10n.accountHintSixDigitCode,
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? l10n.accountValidationEnterVerificationCode
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 100,
                      child: FilledButton(
                        onPressed: (_codeSending || _cooldown > 0)
                            ? null
                            : _sendCode,
                        child: Text(
                          _codeSending
                              ? l10n.accountSendingCode
                              : _cooldown > 0
                              ? l10n.codeCooldownSeconds(_cooldown)
                              : l10n.accountSendVerificationCode,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _newCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.accountLabelNewPassword,
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return l10n.accountValidationEnterNewPassword;
                    }
                    if (v.length < 6) {
                      return l10n.accountValidationNewPasswordMinLength;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.accountLabelConfirmNewPassword,
                  ),
                  validator: (v) {
                    if (v != _newCtrl.text) {
                      return l10n.accountValidationPasswordMismatch;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: (_submitting || codeEmpty) ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.confirm),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  final String email;
  const _DeleteAccountDialog({required this.email});

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _codeCtrl = TextEditingController();
  bool _codeSending = false;
  bool _submitting = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldown = 60;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) {
          _cooldownTimer?.cancel();
          _cooldownTimer = null;
        }
      });
    });
  }

  Future<void> _sendCode() async {
    setState(() {
      _error = null;
      _codeSending = true;
    });
    try {
      await sendDeleteAccountCode();
      if (!mounted) return;
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _codeSending = false);
    }
  }

  Future<void> _confirmDelete() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(
          context,
        ).accountValidationEnterVerificationCode,
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await confirmDeleteAccount(code);
      await ref.read(authProvider.notifier).clearAuth();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final codeEmpty = _codeCtrl.text.trim().isEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSize.formMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    l10n.accountDeleteTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      foregroundColor: colors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.accountDeleteWarning,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                widget.email,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.dangerSurface,
                    borderRadius: AppRadius.small,
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: colors.danger, fontSize: 13),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: l10n.accountLabelVerificationCode,
                        hintText: l10n.accountHintSixDigitCode,
                        counterText: '',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 100,
                    child: FilledButton(
                      onPressed: (_codeSending || _cooldown > 0)
                          ? null
                          : _sendCode,
                      child: Text(
                        _codeSending
                            ? l10n.accountSendingCode
                            : _cooldown > 0
                            ? l10n.codeCooldownSeconds(_cooldown)
                            : l10n.accountSendVerificationCode,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: (_submitting || codeEmpty) ? null : _confirmDelete,
                style: FilledButton.styleFrom(backgroundColor: colors.danger),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.accountDeleteForever),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
