import 'dart:async';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../api/api.dart';
import '../device_id.dart';
import '../logger.dart';
import '../l10n/generated/app_localizations.dart';
import '../preferences/country_cluster.dart';
import '../preferences/locale_region_store.dart';
import '../providers/auth_provider.dart';
import '../providers/auth_session_provider.dart';
import '../services/analytics/analytics.dart';
import '../services/analytics/analytics_events.dart';
import '../ui/app_ui.dart';
import '../widgets/legal_doc_links_row.dart';
import 'qr_display_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.onOfflineMode});

  /// Bootstrap flow: enter app without signing in (offline/local features).
  final VoidCallback? onOfflineMode;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _AuthMode { login, register }

enum _LoginMethod { password, code }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  _AuthMode _authMode = _AuthMode.login;
  _LoginMethod _loginMethod = _LoginMethod.code;
  bool _obscurePassword = true;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _code = TextEditingController();
  String? error;
  bool loading = false;
  bool codeSending = false;
  int codeCooldown = 0;
  Timer? _cooldownTimer;

  bool get _isRegister => _authMode == _AuthMode.register;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => codeCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        codeCooldown--;
        if (codeCooldown <= 0) {
          _cooldownTimer?.cancel();
          _cooldownTimer = null;
        }
      });
    });
  }

  Future<void> _sendCode({String? type}) async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      if (!mounted) return;
      setState(
        () => error = AppLocalizations.of(context).loginErrorEmailRequired,
      );
      return;
    }
    setState(() {
      error = null;
      codeSending = true;
    });
    try {
      final deviceId = await getOrCreateDeviceId();
      final platform = await getAuthPlatformLabel();
      await sendVerificationCode(
        email,
        type: type,
        deviceId: type == 'LOGIN' ? deviceId : null,
        platform: type == 'LOGIN' ? platform : null,
      );
      if (!mounted) return;
      _startCooldown();
      Analytics.track(AnalyticsEvents.verificationCodeSend, {
        'code_type': type ?? 'REGISTER',
        'result': 'success',
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = formatApiError(e));
      Analytics.track(AnalyticsEvents.verificationCodeSend, {
        'code_type': type ?? 'REGISTER',
        'result': 'fail',
      });
    } finally {
      if (mounted) setState(() => codeSending = false);
    }
  }

  Future<void> _sendCodeForLogin() async {
    await _sendCode(type: 'LOGIN');
  }

  Future<void> _submitCodeLogin() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    if (code.length != 6) {
      if (!mounted) return;
      setState(
        () => error = AppLocalizations.of(context).loginErrorCodeSixDigits,
      );
      return;
    }
    setState(() {
      error = null;
      loading = true;
    });
    try {
      final deviceId = await getOrCreateDeviceId();
      final platform = await getAuthPlatformLabel();
      final auth = await loginByCode(
        email,
        code,
        deviceId: deviceId,
        platform: platform,
      );
      await ref.read(authProvider.notifier).login(auth);
      ref.read(authSessionControllerProvider.notifier).onLoginSuccess();
      if (!mounted) return;
      logAuth.info('login_screen code login success, back to chat');
      Analytics.track(AnalyticsEvents.loginCodeSubmit, {
        'result': 'success',
        'length_bucket': Analytics.lengthBucket(code.length),
      });
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      logAuth.warning('login_screen code login failed: $e');
      setState(() => error = formatApiError(e));
      Analytics.track(AnalyticsEvents.loginCodeSubmit, {
        'result': 'fail',
        'length_bucket': Analytics.lengthBucket(code.length),
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    logAuth.info(
      'login_screen submit ${_isRegister ? "register" : "login"} email=$email',
    );
    setState(() {
      error = null;
      loading = true;
    });
    try {
      final deviceId = await getOrCreateDeviceId();
      final platform = await getAuthPlatformLabel();
      final auth = _isRegister
          ? await register(
              email,
              _password.text,
              _code.text.trim(),
              username: _username.text.trim().isEmpty
                  ? null
                  : _username.text.trim(),
              deviceId: deviceId,
              platform: platform,
            )
          : await login(
              email,
              _password.text,
              deviceId: deviceId,
              platform: platform,
            );
      await ref.read(authProvider.notifier).login(auth);
      ref.read(authSessionControllerProvider.notifier).onLoginSuccess();
      if (!mounted) return;
      logAuth.info('login_screen success, back to chat');
      Analytics.track(
        _isRegister
            ? AnalyticsEvents.registerSubmit
            : AnalyticsEvents.loginSubmit,
        {
          'result': 'success',
          'length_bucket': Analytics.lengthBucket(email.length),
        },
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      logAuth.warning('login_screen failed: $e');
      setState(() => error = formatApiError(e));
      Analytics.track(
        _isRegister
            ? AnalyticsEvents.registerSubmit
            : AnalyticsEvents.loginSubmit,
        {
          'result': 'fail',
          'length_bucket': Analytics.lengthBucket(email.length),
        },
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _goQrLogin() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QrDisplayScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.onOfflineMode == null,
        title: Text(
          zh ? '返回虾传' : 'ShrimpSend',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [_buildCountryRegionAction(context, theme, colors, l10n)],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Image.asset(
                        'assets/logo.png',
                        width: 42,
                        height: 42,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isRegister
                          ? (zh ? '创建账号' : 'Create an account')
                          : (zh ? '登录虾传' : 'Sign in to ShrimpSend'),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      zh
                          ? '购买会员、分配设备名额。日常传输无需登录。'
                          : 'Purchase a membership and manage device slots. Everyday transfers need no account.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildFormCard(
                      theme,
                      colors,
                      scheme,
                      l10n,
                      theme.brightness == Brightness.dark,
                    ),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () => setState(() {
                              _authMode = _isRegister
                                  ? _AuthMode.login
                                  : _AuthMode.register;
                              _loginMethod = _LoginMethod.code;
                              error = null;
                            }),
                      child: Text(
                        _isRegister
                            ? (zh
                                  ? '已有账号？登录'
                                  : 'Already have an account? Sign in')
                            : (zh ? '没有账号？注册' : 'New here? Create an account'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const LegalDocLinksRow(compact: true),
                    if (widget.onOfflineMode == null)
                      TextButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst),
                        child: Text(
                          zh ? '继续免登录使用' : 'Continue without signing in',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard(
    ThemeData theme,
    AppThemeColors colors,
    ColorScheme scheme,
    AppLocalizations l10n,
    bool isDark,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_authMode == _AuthMode.login) ...[
              Align(
                alignment: Alignment.center,
                child: IntrinsicWidth(
                  child: SegmentedButton<_LoginMethod>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return scheme.primaryContainer.withValues(alpha: 0.6);
                        }
                        return colors.surfaceMuted;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return scheme.onPrimaryContainer;
                        }
                        return colors.textSecondary;
                      }),
                    ),
                    segments: [
                      ButtonSegment<_LoginMethod>(
                        value: _LoginMethod.password,
                        label: Text(l10n.loginMethodPassword),
                        icon: Icon(LucideIcons.lock, size: 14),
                      ),
                      ButtonSegment<_LoginMethod>(
                        value: _LoginMethod.code,
                        label: Text(l10n.loginMethodCode),
                        icon: Icon(LucideIcons.mail, size: 14),
                      ),
                    ],
                    selected: {_loginMethod},
                    onSelectionChanged: (Set<_LoginMethod> selected) {
                      setState(() {
                        _loginMethod = selected.first;
                        error = null;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.fieldEmail,
                hintText: l10n.hintEmail,
                prefixIcon: Icon(
                  LucideIcons.mail,
                  size: 18,
                  color: colors.textTertiary,
                ),
              ),
            ),
            if ((_authMode == _AuthMode.login &&
                    _loginMethod == _LoginMethod.password) ||
                _isRegister) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                textInputAction: _isRegister
                    ? TextInputAction.next
                    : TextInputAction.done,
                onSubmitted: _isRegister ? null : (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.fieldPassword,
                  prefixIcon: Icon(
                    LucideIcons.lock,
                    size: 18,
                    color: colors.textTertiary,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
            ],
            if (_authMode == _AuthMode.login &&
                _loginMethod == _LoginMethod.code) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitCodeLogin(),
                      decoration: InputDecoration(
                        labelText: l10n.fieldVerificationCode,
                        hintText: l10n.hintVerificationCode6,
                        counterText: '',
                        prefixIcon: Icon(
                          LucideIcons.shieldCheck,
                          size: 18,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 112,
                    height: AppSize.controlHeight,
                    child: OutlinedButton(
                      onPressed: (codeSending || codeCooldown > 0)
                          ? null
                          : _sendCodeForLogin,
                      child: codeSending
                          ? SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.textTertiary,
                              ),
                            )
                          : Text(
                              codeCooldown > 0
                                  ? l10n.codeCooldownSeconds(codeCooldown)
                                  : l10n.loginGetVerificationCode,
                              textAlign: TextAlign.center,
                            ),
                    ),
                  ),
                ],
              ),
            ],
            if (_isRegister) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _username,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.fieldNicknameOptional,
                  hintText: l10n.hintDisplayName,
                  prefixIcon: Icon(
                    LucideIcons.user,
                    size: 18,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ],
            if (_isRegister) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: l10n.fieldVerificationCode,
                        hintText: l10n.hintVerificationCode6,
                        counterText: '',
                        prefixIcon: Icon(
                          LucideIcons.shieldCheck,
                          size: 18,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 112,
                    height: AppSize.controlHeight,
                    child: OutlinedButton(
                      onPressed: (codeSending || codeCooldown > 0)
                          ? null
                          : _sendCode,
                      child: codeSending
                          ? SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.textTertiary,
                              ),
                            )
                          : Text(
                              codeCooldown > 0
                                  ? l10n.codeCooldownSeconds(codeCooldown)
                                  : l10n.loginSendVerificationCode,
                              textAlign: TextAlign.center,
                            ),
                    ),
                  ),
                ],
              ),
            ],
            _buildError(theme, colors),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: loading
                  ? null
                  : (_isRegister
                        ? _submit
                        : (_loginMethod == _LoginMethod.code
                              ? _submitCodeLogin
                              : _submit)),
              child: loading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Text(
                      _isRegister
                          ? l10n.loginSubmitRegister
                          : (_loginMethod == _LoginMethod.code
                                ? l10n.loginSubmitWithCode
                                : l10n.loginSubmitPassword),
                    ),
            ),
            if (_authMode == _AuthMode.login) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _goQrLogin,
                icon: const Icon(LucideIcons.qrCode, size: 18),
                label: Text(l10n.loginQrLogin),
              ),
            ],
            if (widget.onOfflineMode != null) ...[
              const SizedBox(height: AppSpacing.md),
              _buildOfflineModeButton(l10n),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineModeButton(AppLocalizations l10n) {
    return OutlinedButton.icon(
      onPressed: () {
        Analytics.track(AnalyticsEvents.offlineModeEnter);
        widget.onOfflineMode!();
      },
      icon: const Icon(LucideIcons.cloudOff, size: 18),
      label: Text(l10n.enterOfflineMode),
    );
  }

  Widget _buildError(ThemeData theme, AppThemeColors colors) {
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.dangerSurface,
          borderRadius: AppRadius.small,
          border: Border.all(color: colors.danger.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.circleAlert, size: 16, color: colors.danger),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _countryLabelForCode(BuildContext context, String countryCode) {
    final c = CountryService().findByCode(countryCode);
    if (c == null) {
      return countryCode;
    }
    return c.getTranslatedName(context) ?? c.name;
  }

  /// Normalizes stored locale to `zh_CN` or `en` for the language segment control.
  Locale _localeSegmentValue(Locale locale) {
    if (locale.languageCode == 'zh') {
      return const Locale('zh', 'CN');
    }
    return const Locale('en');
  }

  String _localeEchoLabel(Locale locale, AppLocalizations l10n) {
    final v = _localeSegmentValue(locale);
    return v.languageCode == 'zh'
        ? l10n.localeNameZhHans
        : l10n.localeNameEnglish;
  }

  Widget _buildCountryRegionAction(
    BuildContext context,
    ThemeData theme,
    AppThemeColors colors,
    AppLocalizations l10n,
  ) {
    final store = LocaleRegionStoreScope.of(context);
    return ListenableBuilder(
      listenable: store.notifier,
      builder: (context, _) {
        final lr = store.notifier.value;
        final echo =
            '${_countryLabelForCode(context, lr.countryCode)} · ${_localeEchoLabel(lr.locale, l10n)}';
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: TextButton.icon(
              onPressed: () =>
                  _showLocaleRegionDialog(context, theme, colors, store, l10n),
              icon: Icon(
                LucideIcons.languages,
                size: 16,
                color: colors.textSecondary,
              ),
              label: Text(
                echo,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        );
      },
    );
  }

  static const _countryPickerFavorites = <String>[
    'CN',
    'US',
    'HK',
    'TW',
    'JP',
    'SG',
    'GB',
    'AU',
    'CA',
    'DE',
    'FR',
  ];

  void _showLocaleRegionDialog(
    BuildContext parentContext,
    ThemeData theme,
    AppThemeColors colors,
    LocaleRegionStore store,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: parentContext,
      useRootNavigator: true,
      builder: (dialogContext) {
        return ValueListenableBuilder<LocaleRegionState>(
          valueListenable: store.notifier,
          builder: (context, lr, _) {
            return AlertDialog(
              title: Text(
                LocaleRegionStore.countryLocked
                    ? l10n.sectionLanguage
                    : l10n.sectionLanguageRegion,
              ),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!LocaleRegionStore.countryLocked) ...[
                        Text(
                          l10n.fieldCountryRegion,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        ListTile(
                          tileColor: colors.surfaceMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.medium,
                            side: BorderSide(color: colors.borderStrong),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          title: Text(
                            _countryLabelForCode(context, lr.countryCode),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: Icon(
                            LucideIcons.chevronRight,
                            size: 18,
                            color: colors.textTertiary,
                          ),
                          onTap: () {
                            showCountryPicker(
                              context: dialogContext,
                              useRootNavigator: true,
                              showWorldWide: false,
                              favorite: _countryPickerFavorites,
                              onSelect: (Country country) {
                                final dialogNav = Navigator.maybeOf(
                                  dialogContext,
                                  rootNavigator: true,
                                );
                                Future.microtask(
                                  () => _applyPickedCountry(
                                    store,
                                    lr,
                                    l10n,
                                    country,
                                    localeDialogNavigator: dialogNav,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      Text(
                        l10n.fieldLanguage,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceMuted,
                          borderRadius: AppRadius.medium,
                          border: Border.all(color: colors.borderStrong),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Align(
                            alignment: Alignment.center,
                            child: SegmentedButton<Locale>(
                              showSelectedIcon: false,
                              segments: [
                                ButtonSegment<Locale>(
                                  value: const Locale('zh', 'CN'),
                                  label: Text(l10n.localeNameZhHans),
                                ),
                                ButtonSegment<Locale>(
                                  value: const Locale('en'),
                                  label: Text(l10n.localeNameEnglish),
                                ),
                              ],
                              selected: {_localeSegmentValue(lr.locale)},
                              onSelectionChanged: (Set<Locale> selected) async {
                                final next = selected.first;
                                if (_localeSegmentValue(lr.locale) == next) {
                                  return;
                                }
                                await store.setLocale(next);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(l10n.cancel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _applyPickedCountry(
    LocaleRegionStore store,
    LocaleRegionState current,
    AppLocalizations l10n,
    Country country, {
    NavigatorState? localeDialogNavigator,
  }) async {
    if (LocaleRegionStore.countryLocked) return;
    final newCode = country.countryCode;
    if (newCode == current.countryCode) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!mounted || !context.mounted) {
      return;
    }

    final beforeCluster = serviceRegionForCountryCode(current.countryCode);
    final snapshot = LocaleRegionState(
      locale: current.locale,
      countryCode: current.countryCode,
      localeGateCompleted: current.localeGateCompleted,
    );
    final clusterSwitch = beforeCluster != serviceRegionForCountryCode(newCode);
    final loggedIn = ref.read(authProvider).isLoggedIn;

    if (clusterSwitch && loggedIn) {
      localeDialogNavigator?.pop();
      await Future<void>.delayed(Duration.zero);
      if (!mounted || !context.mounted) {
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.serverClusterSwitchTitle),
          content: Text(l10n.serverClusterSwitchMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (ok != true || !mounted || !context.mounted) {
        return;
      }
      await ref.read(authProvider.notifier).clearAuth();
      await store.restoreState(snapshot);
      if (!mounted || !context.mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (_) => false);
      return;
    }

    await store.setCountryCode(newCode);
  }
}
