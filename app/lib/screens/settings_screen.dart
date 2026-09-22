import '../ui/device_name_dialog.dart';
import 'dart:async';
import 'dart:io';

import 'package:country_picker/country_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_desktop_updater/flutter_desktop_updater.dart'
    as desktop_upd;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../api/api.dart';
import '../color_theme.dart';
import '../color_theme_store.dart';
import '../config/env.dart';
import '../legal/open_source_urls.dart';
import '../l10n/generated/app_localizations.dart';
import '../preferences/clipboard_preferences.dart';
import '../preferences/country_cluster.dart';
import '../preferences/locale_region_store.dart';
import '../providers/auth_provider.dart';
import '../file_save_preferences.dart';
import '../logger.dart';
import '../providers/app_update_provider.dart';
import '../theme_store.dart';
import '../ui/app_ui.dart';
import '../ui/product_scaffold.dart';
import '../device_id.dart';
import '../providers/device_provider.dart';
import '../utils/effective_save_dir_display.dart';
import '../utils/gallery_permission.dart';
import '../utils/toast.dart';
import '../services/app_update_service.dart';
import '../services/analytics/analytics.dart';
import '../services/analytics/analytics_events.dart';
import '../widgets/app_update_dialog.dart';
import '../widgets/legal_doc_links_row.dart';
import '../screens/product_feedback_screen.dart';
import '../services/file_store.dart';
import '../services/receive_dir_resolver.dart';
import '../services/received_file_dao.dart';
import '../services/saf_storage_service.dart';
import '../services/windows_launch_at_startup_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  /// When true (e.g. mobile home tab), hide back [leading] — no route to pop.
  final bool embedded;

  final String initialTab;
  final bool help;
  const SettingsScreen({
    super.key,
    this.embedded = false,
    this.initialTab = 'general',
    this.help = false,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  bool _loading = true;
  String _localDeviceName = '';
  late String _activeTab;
  bool _saveToGallery = false;
  bool _windowsLaunchAtStartup = false;
  bool _autoCopyReceivedText = true;
  String? _customSaveDir;
  String? _customSaveTreeUri;
  String _effectiveSaveDir = '';
  ReceiveDirResolution? _receiveDirResolution;
  ReceiveDirFallbackInfo? _receiveDirFallback;
  UserProfile? _profile;
  MembershipMe? _membership;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    getDeviceName().then((value) {
      if (mounted) setState(() => _localDeviceName = value);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final loggedIn = ref.read(authProvider).isLoggedIn;
      final values = await Future.wait<dynamic>([
        getSaveToGallery(),
        getAutoCopyReceivedText(),
        Platform.isAndroid ? getCustomSaveTreeUri() : getCustomSaveDir(),
        FileStore.getReceiveDirResolution(),
        getReceiveDirFallback(),
        Platform.isWindows
            ? WindowsLaunchAtStartupService.getEnabledPreference()
            : Future.value(false),
        loggedIn
            ? fetchUserProfile()
                  .then<UserProfile?>((value) => value)
                  .catchError((_) => null)
            : Future.value(null),
        loggedIn
            ? fetchMyMembership()
                  .then<MembershipMe?>((value) => value)
                  .catchError((_) => null)
            : Future.value(null),
      ]);
      if (!mounted) return;
      final resolution = values[3] as ReceiveDirResolution;
      setState(() {
        _saveToGallery = values[0] as bool;
        _autoCopyReceivedText = values[1] as bool;
        _customSaveDir = Platform.isAndroid ? null : values[2] as String?;
        _customSaveTreeUri =
            resolution.customSafTreeUri ??
            (Platform.isAndroid ? values[2] as String? : null);
        _effectiveSaveDir = _formatEffectiveSaveDir(resolution);
        _receiveDirResolution = resolution;
        _receiveDirFallback = values[4] as ReceiveDirFallbackInfo?;
        _windowsLaunchAtStartup = values[5] as bool;
        _profile = values[6] as UserProfile?;
        _membership = values[7] as MembershipMe?;
      });
    } catch (error) {
      logSettings.warning('settings load failed: $error');
    }
    if (mounted) setState(() => _loading = false);
  }

  EdgeInsets _settingsBodyPadding() {
    return EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.xs,
      AppSpacing.md,
      AppSpacing.lg + (widget.embedded ? 0.0 : 0),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
    final colors = context.appColors;

    Widget placeholder({
      required double width,
      required double height,
      BorderRadius? borderRadius,
    }) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: borderRadius ?? AppRadius.small,
        ),
      );
    }

    Widget row({double titleWidth = 160, double subtitleWidth = 220}) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            placeholder(
              width: AppSize.settingsIcon,
              height: AppSize.settingsIcon,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  placeholder(width: titleWidth, height: 14),
                  const SizedBox(height: AppSpacing.xs),
                  placeholder(width: subtitleWidth, height: 11),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: _settingsBodyPadding(),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSize.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: placeholder(width: 96, height: 12),
                ),
                const SizedBox(height: AppSpacing.xs),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      row(),
                      const Divider(height: 1),
                      row(titleWidth: 136, subtitleWidth: 180),
                      const Divider(height: 1),
                      row(titleWidth: 148, subtitleWidth: 210),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: placeholder(width: 88, height: 12),
                ),
                const SizedBox(height: AppSpacing.xs),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      row(titleWidth: 128, subtitleWidth: 200),
                      const Divider(height: 1),
                      row(titleWidth: 156, subtitleWidth: 240),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final wide = MediaQuery.sizeOf(context).width >= 768;
    final loggedIn = ref.watch(authProvider).isLoggedIn;
    final help = widget.help;
    Widget row(
      String title,
      String description,
      Widget trailing, {
      VoidCallback? onTap,
    }) => Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        title: Text(title),
        subtitle: description.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: colors.textSecondary,
                  ),
                ),
              ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
    Widget nav(String title, String description, String route, IconData icon) =>
        row(
          title,
          description,
          Icon(icon, size: 19, color: colors.textSecondary),
          onTap: () => openProductRoute(context, route),
        );
    final sections = <Widget>[];
    if (help) {
      sections.addAll([
        Row(
          children: [
            Image.asset('assets/logo.png', width: 48, height: 48),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zh ? '虾传' : 'Shrimpsend',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                ref
                    .watch(packageInfoProvider)
                    .when(
                      data: (info) => Text(
                        '${info.version} (${info.buildNumber})',
                        style: theme.textTheme.bodySmall,
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_isDesktop)
          _buildDesktopUpdateSection(context)
        else
          ValueListenableBuilder<UpdateState>(
            valueListenable: ref.read(appUpdateServiceProvider).state,
            builder: (context, value, _) => _buildUpdateSection(context, value),
          ),
        nav(
          zh ? '版本历史' : 'Version history',
          '',
          '/settings/version-history',
          LucideIcons.history,
        ),
          row(
            zh ? '问题反馈' : 'Feedback',
            zh ? '告诉我们遇到的问题或建议' : 'Share a problem or suggestion',
            const Icon(LucideIcons.messageSquare, size: 19),
            onTap: () => unawaited(_openFeedback(context)),
          ),
        nav(
          zh ? '运行日志' : 'Activity log',
          zh ? '查看和导出本机运行记录' : 'View and export local activity',
          '/settings/app-log',
          LucideIcons.fileText,
        ),
        row(
          zh ? '开源代码' : 'Source code',
          '',
          const Icon(LucideIcons.externalLink, size: 19),
          onTap: () => launchExternalUrl(kOpenSourceRepoUrl),
        ),
        const SizedBox(height: 24),
        const LegalDocLinksRow(compact: true),
      ]);
    } else if (_activeTab == 'general') {
      sections.addAll([
        row(
          zh ? '设备名称' : 'Device name',
          _localDeviceName,
          OutlinedButton(
            onPressed: _renameLocalDevice,
            child: Text(zh ? '修改' : 'Edit'),
          ),
        ),
        row(
          l10n.settingsAutoCopyReceivedTextTitle,
          l10n.settingsAutoCopyReceivedTextSubtitle,
          Switch(
            value: _autoCopyReceivedText,
            onChanged: (value) async {
              await setAutoCopyReceivedText(value);
              if (mounted) setState(() => _autoCopyReceivedText = value);
            },
          ),
        ),
        nav(
          zh ? '设备身份' : 'Device identity',
          zh ? '备份身份，重装后恢复配对与授权' : 'Back up your identity before reinstalling',
          '/settings/device-identity',
          LucideIcons.fingerprint,
        ),
        if (Platform.isWindows)
          row(
            l10n.settingsWindowsLaunchAtStartupTitle,
            l10n.settingsWindowsLaunchAtStartupSubtitle,
            Switch(
              value: _windowsLaunchAtStartup,
              onChanged: (value) async {
                try {
                  await WindowsLaunchAtStartupService.setEnabled(value);
                  if (mounted) setState(() => _windowsLaunchAtStartup = value);
                } catch (_) {
                  if (context.mounted)
                    AppToast.show(
                      context,
                      message: l10n.settingsWindowsLaunchAtStartupFailed,
                    );
                }
              },
            ),
          ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            zh
                ? '无需登录即可传输。设备授权只提供本机服务权益，文件和历史始终由各台设备独立保存。'
                : 'Transfer without signing in. Authorization grants service benefits; each device keeps its own files and history.',
            style: TextStyle(
              fontSize: 12,
              height: 1.8,
              color: colors.textSecondary,
            ),
          ),
        ),
        if (!wide) ...[
          const SizedBox(height: 24),
          nav(
            zh ? '本机授权' : 'Authorization',
            zh ? '输入授权码或扫码' : 'Enter a code or scan',
            '/authorize',
            LucideIcons.shieldCheck,
          ),
          nav(
            zh ? '会员与名额' : 'Membership & slots',
            _membership?.tierName ??
                (zh ? '一个账号购买，按设备分配' : 'Purchase once and assign device slots'),
            loggedIn ? '/settings/membership' : '/login',
            LucideIcons.badgeCheck,
          ),
          nav(
            zh ? '账号' : 'Account',
            _profile?.email ??
                (zh ? '登录购买账号' : 'Sign in to your purchasing account'),
            loggedIn ? '/account' : '/login',
            LucideIcons.userRound,
          ),
          nav(zh ? '帮助' : 'Help', '', '/settings/help', LucideIcons.circleHelp),
        ],
      ]);
    } else if (_activeTab == 'receiving') {
      sections.addAll([
        row(
          l10n.settingsFileSavePath,
          _effectiveSaveDir,
          const Icon(LucideIcons.folderDown, size: 24),
          onTap: _showReceiveDirFallbackWarning,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (!Platform.isIOS)
              OutlinedButton.icon(
                onPressed: _selectCustomSaveDir,
                icon: const Icon(LucideIcons.folderOpen, size: 17),
                label: Text(l10n.settingsChooseFolder),
              ),
            TextButton(
              onPressed: _customSaveDir == null && _customSaveTreeUri == null
                  ? null
                  : _restoreDefaultSaveDir,
              child: Text(l10n.settingsRestoreDefaultPath),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          zh
              ? '收到的文件直接保存到目标位置。同名文件自动保留新副本，不覆盖已有文件。'
              : 'Received files save directly to the destination. Existing files are kept when names conflict.',
          style: TextStyle(
            fontSize: 12,
            height: 1.8,
            color: colors.textSecondary,
          ),
        ),
        if (Platform.isAndroid || Platform.isIOS)
          row(
            l10n.settingsSaveToGalleryTitle,
            l10n.settingsSaveToGallerySubtitle,
            Switch(
              value: _saveToGallery,
              onChanged: (value) async {
                if (value && !await requestSaveToGalleryPermission()) {
                  if (context.mounted)
                    AppToast.show(
                      context,
                      message: l10n.settingsGalleryPermissionToast,
                    );
                  return;
                }
                await setSaveToGallery(value);
                if (mounted) setState(() => _saveToGallery = value);
              },
            ),
          ),
      ]);
    } else if (_activeTab == 'appearance') {
      sections.addAll([
        Text(zh ? '显示模式' : 'Display mode', style: theme.textTheme.titleSmall),
        const SizedBox(height: 16),
        _ThemeSegment(store: ThemeStoreScope.of(context)),
        const SizedBox(height: 32),
        Text(l10n.settingsColorThemeLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: 20),
        _ColorThemePicker(store: ColorThemeStoreScope.of(context)),
      ]);
    } else if (_activeTab == 'language') {
      sections.add(
        ValueListenableBuilder<LocaleRegionState>(
          valueListenable: LocaleRegionStoreScope.of(context).notifier,
          builder: (context, lr, _) => Column(
            children: [
              row(
                l10n.fieldLanguage,
                _languageDisplayLabel(lr.locale, l10n),
                const Icon(LucideIcons.chevronRight, size: 18),
                onTap: _pickLanguage,
              ),
              if (!LocaleRegionStore.countryLocked)
                row(
                  l10n.fieldCountryRegion,
                  _countryDisplayLabel(context, lr.countryCode),
                  const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: _pickRegion,
                ),
            ],
          ),
        ),
      );
    }
    return ProductScaffold(
      embedded: widget.embedded,
      settingsLocation: help ? '/settings/help' : '/settings',
      appBar: AppBar(
        automaticallyImplyLeading: !wide && !widget.embedded,
        toolbarHeight: wide ? 80 : 64,
        titleSpacing: wide ? 36 : 20,
        title: Text(
          help ? (zh ? '帮助' : 'Help') : (zh ? '本机设置' : 'Device settings'),
          style: TextStyle(
            fontSize: wide ? 24 : 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!help)
            ProductPreferencesTabs(
              selected: _activeTab,
              onChanged: (tab) {
                if (ProductWorkspaceScope.maybeOf(context) != null ||
                    tab == 'fonts' || tab == 'shortcuts') {
                  openProductRoute(context, tab == 'general' ? '/settings' : '/settings/$tab');
                } else {
                  setState(() => _activeTab = tab);
                }
              },
            ),
          Expanded(
            child: _loading
                ? _buildLoadingSkeleton(context)
                : ListView(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 36 : 20,
                      24,
                      wide ? 36 : 20,
                      widget.embedded ? 0.0 + 24 : 32,
                    ),
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 780),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: sections,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameLocalDevice() async {
    final value = await showDialog<String>(context: context, builder: (_) => DeviceNameDialog(initialName: _localDeviceName));
    if (value == null) return;
    await setDeviceName(value);
    ref.invalidate(deviceInfoProvider);
    if (mounted) setState(() => _localDeviceName = value);
  }

  Future<void> _openFeedback(BuildContext context) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFeedbackScreen()));
  }

  String _desktopUpdateSubtitle(AppLocalizations l10n) {
    final m = desktop_upd.UpdateManager();
    switch (m.status) {
      case desktop_upd.UpdateStatus.initial:
        return l10n.desktopUpdateTapCheck;
      case desktop_upd.UpdateStatus.checking:
        return l10n.desktopUpdateChecking;
      case desktop_upd.UpdateStatus.updateAvailable:
        return l10n.desktopUpdateAvailableUseBanner;
      case desktop_upd.UpdateStatus.updating:
        return l10n.desktopUpdateDownloadingPercent(
          (m.progress * 100).toStringAsFixed(0),
        );
      case desktop_upd.UpdateStatus.readyToRestart:
        return l10n.desktopUpdateReadyRestart;
      case desktop_upd.UpdateStatus.restarting:
        return l10n.desktopUpdateRestarting;
      case desktop_upd.UpdateStatus.error:
        return m.error ?? l10n.desktopUpdateCheckFailed;
    }
  }

  Widget _buildDesktopUpdateSection(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: desktop_upd.UpdateManager(),
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        return _buildCard(
          children: [
            _buildNavItem(
              context: context,
              icon: LucideIcons.download,
              iconBgColor: theme.colorScheme.primary.withValues(alpha: 0.12),
              iconColor: theme.colorScheme.primary,
              title: l10n.settingsCheckUpdate,
              subtitle: desktop_upd.UpdateConfig().isConfigured
                  ? _desktopUpdateSubtitle(l10n)
                  : l10n.desktopUpdateNotConfiguredHint,
              onTap: () {
                if (!desktop_upd.UpdateConfig().isConfigured) {
                  AppToast.show(
                    context,
                    message: l10n.desktopToastUpdateNotConfigured,
                  );
                  return;
                }
                _onDesktopCheckUpdate(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _onDesktopCheckUpdate(BuildContext context) async {
    if (!desktop_upd.UpdateConfig().isConfigured) return;
    await desktop_upd.UpdateManager().checkForUpdate();
    if (!mounted || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    final m = desktop_upd.UpdateManager();
    if (m.status == desktop_upd.UpdateStatus.error) {
      AppToast.show(context, message: m.error ?? l10n.desktopToastCheckFailed);
      return;
    }
    if (m.status == desktop_upd.UpdateStatus.updateAvailable) {
      AppToast.show(context, message: l10n.desktopToastNewVersionUseBanner);
      return;
    }
    if (m.status == desktop_upd.UpdateStatus.initial) {
      AppToast.show(context, message: l10n.desktopToastAlreadyLatest);
    }
  }

  Widget _buildUpdateSection(BuildContext context, UpdateState updateState) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final service = ref.read(appUpdateServiceProvider);

    if (Platform.isAndroid && Env.androidPlayDistribution) {
      return _buildCard(
        children: [
          _buildNavItem(
            context: context,
            icon: LucideIcons.download,
            iconBgColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            iconColor: theme.colorScheme.primary,
            title: l10n.settingsCheckUpdate,
            subtitle: l10n.updateStatusPlayManaged,
            onTap: () => _openPlayStoreListing(context),
          ),
        ],
      );
    }

    return _buildCard(
      children: [
        _buildNavItem(
          context: context,
          icon: LucideIcons.download,
          iconBgColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          iconColor: theme.colorScheme.primary,
          title: l10n.settingsCheckUpdate,
          subtitle: _updateStatusSubtitle(updateState, l10n),
          onTap: () => _onCheckUpdate(context, service),
        ),
        if (updateState.status == UpdateStatus.downloading)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: updateState.progress),
                const SizedBox(height: 4),
                Text(
                  l10n.mobileUpdateDownloadingPercent(
                    (updateState.progress * 100).toStringAsFixed(0),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        if (updateState.status == UpdateStatus.downloaded &&
            updateState.downloadedPath != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.mobileUpdateDownloadedInstall,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.success,
                  ),
                ),
                if (updateState.downloadedVersion != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.appUpdateDownloadedVersionLabel(
                      updateState.downloadedVersion!,
                      '${updateState.info?.buildNumber ?? '—'}',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.appUpdateDownloadedFileLabel(
                      p.basename(updateState.downloadedPath!),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () =>
                          _installApk(context, updateState.downloadedPath!),
                      child: Text(l10n.mobileUpdateInstall),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (updateState.status == UpdateStatus.error &&
            updateState.errorMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    updateState.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.danger,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => service.checkForUpdate(),
                  child: Text(l10n.commonRetry),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _updateStatusSubtitle(UpdateState s, AppLocalizations l10n) {
    switch (s.status) {
      case UpdateStatus.idle:
        return l10n.updateStatusAlreadyLatest;
      case UpdateStatus.checking:
        return l10n.updateStatusChecking;
      case UpdateStatus.updateAvailable:
        return s.info != null
            ? l10n.updateStatusNewVersion(s.info!.version)
            : l10n.updateStatusCheckAction;
      case UpdateStatus.downloading:
        return l10n.updateStatusDownloadingPercent(
          (s.progress * 100).toStringAsFixed(0),
        );
      case UpdateStatus.downloaded:
        if (s.downloadedVersion != null && s.downloadedVersion!.isNotEmpty) {
          return '${l10n.updateStatusDownloadedReady} · v${s.downloadedVersion}';
        }
        return l10n.updateStatusDownloadedReady;
      case UpdateStatus.error:
        return l10n.updateStatusCheckFailed;
    }
  }

  Future<void> _onCheckUpdate(
    BuildContext context,
    AppUpdateService service,
  ) async {
    if (_isDesktop) {
      await _onDesktopCheckUpdate(context);
      return;
    }
    final info = await service.checkForUpdate();
    if (!mounted) return;
    if (!context.mounted) return;
    if (info == null) {
      if (service.state.value.status == UpdateStatus.idle) {
        AppToast.show(
          context,
          message: AppLocalizations.of(context).desktopToastAlreadyLatest,
        );
      }
      return;
    }
    await showAppUpdateAvailableDialog(
      context: context,
      info: info,
      service: service,
      barrierDismissible: true,
      onIosStore: () => launchExternalUrl(info.iosStoreUrl),
    );
  }

  Future<void> _openPlayStoreListing(BuildContext context) async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      await launchExternalUrl(
        'https://play.google.com/store/apps/details?id=${pkg.packageName}',
      );
    } catch (e) {
      logSettings.warning('open play listing failed: $e');
    }
  }

  static const _apkChannel = MethodChannel('dev.ultrasend/apk');

  Future<void> _installApk(BuildContext context, String filePath) async {
    try {
      final installPath = await AppUpdateService.pathForInstall(filePath);
      final res = await _apkChannel.invokeMethod('installApk', {
        'filePath': installPath,
      });
      if (!mounted || !context.mounted) return;
      if (res == null) {
        AppToast.show(
          context,
          message: AppLocalizations.of(context).snackbarAllowInstallUnknownApps,
          duration: const Duration(seconds: 3),
        );
      }
    } on PlatformException catch (e) {
      if (!mounted || !context.mounted) return;
      final loc = AppLocalizations.of(context);
      if (e.code == 'PERMISSION_REQUIRED') {
        AppToast.show(
          context,
          message: loc.snackbarAllowInstallUnknownApps,
          duration: const Duration(seconds: 3),
        );
      } else {
        AppToast.show(
          context,
          message: loc.settingsInstallFailed(e.message ?? ''),
        );
      }
    }
  }

  String _languageDisplayLabel(Locale locale, AppLocalizations l10n) {
    if (locale.languageCode == 'zh') return l10n.localeNameZhHans;
    return l10n.localeNameEnglish;
  }

  String _countryDisplayLabel(BuildContext context, String code) {
    final c = CountryService().findByCode(code);
    if (c == null) return code;
    return c.getTranslatedName(context) ?? c.name;
  }

  Future<void> _pickLanguage() async {
    final store = LocaleRegionStoreScope.of(context);
    final chosen = await showModalBottomSheet<Locale>(
      context: context,
      builder: (ctx) {
        final sheetLoc = AppLocalizations.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(sheetLoc.localeNameZhHans),
                onTap: () => Navigator.pop(ctx, const Locale('zh', 'CN')),
              ),
              ListTile(
                title: Text(sheetLoc.localeNameEnglish),
                onTap: () => Navigator.pop(ctx, const Locale('en')),
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;
    await store.setLocale(chosen);
    Analytics.track(AnalyticsEvents.settingChanged, {
      'key': 'locale',
      'value':
          '${chosen.languageCode}${chosen.countryCode != null ? '_${chosen.countryCode}' : ''}',
    });
  }

  Future<void> _pickRegion() async {
    final store = LocaleRegionStoreScope.of(context);
    final current = store.notifier.value;
    final l10n = AppLocalizations.of(context);

    showCountryPicker(
      context: context,
      useRootNavigator: true,
      showWorldWide: false,
      favorite: const [
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
      ],
      // async 回调若在底部弹窗关闭前触发 showDialog，易导致路由冲突、表现为「点了没反应」；
      // 延后到下一事件循环再执行。
      onSelect: (Country country) {
        Future.microtask(
          () => _applyPickedCountryRegion(country, store, current, l10n),
        );
      },
    );
  }

  Future<void> _applyPickedCountryRegion(
    Country country,
    LocaleRegionStore store,
    LocaleRegionState current,
    AppLocalizations l10n,
  ) async {
    final newCode = country.countryCode;
    if (newCode == current.countryCode) return;

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final beforeCluster = serviceRegionForCountryCode(current.countryCode);
    final snapshot = LocaleRegionState(
      locale: current.locale,
      countryCode: current.countryCode,
      localeGateCompleted: current.localeGateCompleted,
    );

    final clusterSwitch = beforeCluster != serviceRegionForCountryCode(newCode);
    final loggedIn = ref.read(authProvider).isLoggedIn;

    // 与线上/本地无关：只要服务集群（CN vs 非 CN）变化且已登录，即提示退出，便于本地调试复现。
    if (clusterSwitch && loggedIn) {
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
      if (ok != true || !mounted) return;
      await ref.read(authProvider.notifier).clearAuth();
      await store.restoreState(snapshot);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (_) => false);
      return;
    }

    await store.setCountryCode(newCode);
  }

  Widget _buildCard({required List<Widget> children}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: AppSize.settingsIcon,
              height: AppSize.settingsIcon,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: AppRadius.small,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing,
              const SizedBox(width: AppSpacing.xs),
            ],
            Icon(
              LucideIcons.chevronRight,
              color: colors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  bool get _shouldShowReceiveDirFallbackWarning =>
      _receiveDirResolution?.usedFallback == true &&
      _receiveDirFallback != null &&
      !_receiveDirFallback!.isEmpty;

  Future<void> _showReceiveDirFallbackWarning() async {
    if (!_shouldShowReceiveDirFallbackWarning || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final fallback = _receiveDirFallback!;
    final resolution = _receiveDirResolution!;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colors = ctx.appColors;
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.large),
          titlePadding: AppDialog.titlePadding,
          contentPadding: AppDialog.confirmContentPadding,
          actionsPadding: AppDialog.actionsPadding,
          title: Text(l10n.settingsSavePathFallbackDialogTitle),
          content: Text(
            l10n.settingsSavePathFallbackDialogBody(
              fallback.intendedPath,
              resolution.path,
              fallback.fallbackReason.isNotEmpty
                  ? fallback.fallbackReason
                  : '—',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.settingsSavePathFallbackDialogOk),
            ),
          ],
        );
      },
    );
  }

  String _formatEffectiveSaveDir(ReceiveDirResolution resolution) =>
      formatEffectiveSaveDir(resolution);

  Future<void> _selectCustomSaveDir() async {
    if (Platform.isAndroid) {
      try {
        final treeUri = await SafStorageService.pickSaveTree();
        if (treeUri == null || treeUri.trim().isEmpty) return;
        await _applyCustomSaveDir(treeUri);
      } catch (_) {
        if (mounted) {
          AppToast.show(
            context,
            message: AppLocalizations.of(context).settingsSavePathFailedToast,
          );
        }
      }
      return;
    }
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null || dirPath.trim().isEmpty) return;
    await _applyCustomSaveDir(dirPath);
  }

  Future<void> _applyCustomSaveDir(String value) async {
    try {
      if (Platform.isAndroid && value.startsWith('content://')) {
        final ok = await SafStorageService.probeWritable(value);
        if (!ok) {
          throw StateError('SAF tree not writable');
        }
        final displayName = await SafStorageService.getDisplayName(value);
        await setCustomSaveTreeUri(treeUri: value, displayName: displayName);
        await clearReceiveDirFallback();
        FileStore.invalidateReceiveDirCache();
        final resolution = await FileStore.getReceiveDirResolution();
        try {
          await ReceivedFileDao.instance.reconcileWithRoot(resolution.path);
        } catch (e) {
          logChat.warning('reconcileWithRoot failed: $e');
        }
        if (!mounted) return;
        final fallback = await getReceiveDirFallback();
        if (!mounted) return;
        setState(() {
          _customSaveDir = null;
          _customSaveTreeUri = value;
          _effectiveSaveDir = _formatEffectiveSaveDir(resolution);
          _receiveDirResolution = resolution;
          _receiveDirFallback = fallback;
        });
        if (!context.mounted) return;
        AppToast.show(
          context,
          message: AppLocalizations.of(context).settingsSavePathUpdatedToast,
        );
        FileStore.notifyReceiveDirChanged();
        return;
      }

      final dir = Directory(value);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await FileStore.assertWritableDirectory(dir.path);
      final normalizedDirPath = normalizeCustomSaveDirValue(dir.path);
      await setCustomSaveDir(normalizedDirPath);
      await clearReceiveDirFallback();
      FileStore.invalidateReceiveDirCache();
      final resolution = await FileStore.getReceiveDirResolution();
      // Keep existing index rows pointing at the old root — those files are
      // still on disk and should remain visible in the file manager. Just
      // pick up any orphan subdirs that may already be present at the new
      // root so they show up as well.
      try {
        await ReceivedFileDao.instance.reconcileWithRoot(resolution.path);
      } catch (e) {
        logChat.warning('reconcileWithRoot failed: $e');
      }
      if (!mounted) return;
      final fallback = await getReceiveDirFallback();
      if (!mounted) return;
      setState(() {
        _customSaveDir = normalizedDirPath;
        _effectiveSaveDir = _formatEffectiveSaveDir(resolution);
        _receiveDirResolution = resolution;
        _receiveDirFallback = fallback;
      });
      if (!context.mounted) return;
      AppToast.show(
        context,
        message: AppLocalizations.of(context).settingsSavePathUpdatedToast,
      );
      FileStore.notifyReceiveDirChanged();
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: AppLocalizations.of(context).settingsSavePathFailedToast,
        );
      }
    }
  }

  Future<void> _restoreDefaultSaveDir() async {
    try {
      await clearCustomSaveDir();
      FileStore.invalidateReceiveDirCache();
      final resolution = await FileStore.getReceiveDirResolution();
      try {
        await ReceivedFileDao.instance.reconcileWithRoot(resolution.path);
      } catch (e) {
        logChat.warning('reconcileWithRoot failed: $e');
      }
      if (!mounted) return;
      final fallback = await getReceiveDirFallback();
      if (!mounted) return;
      setState(() {
        _customSaveDir = null;
        _customSaveTreeUri = null;
        _effectiveSaveDir = _formatEffectiveSaveDir(resolution);
        _receiveDirResolution = resolution;
        _receiveDirFallback = fallback;
      });
      if (!context.mounted) return;
      AppToast.show(
        context,
        message: AppLocalizations.of(context).settingsSavePathRestoredToast,
      );
      FileStore.notifyReceiveDirChanged();
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: AppLocalizations.of(
            context,
          ).settingsSavePathRestoreFailedToast,
        );
      }
    }
  }
}

class _ThemeSegment extends StatefulWidget {
  const _ThemeSegment({required this.store});

  final ThemeStore store;

  @override
  State<_ThemeSegment> createState() => _ThemeSegmentState();
}

class _ThemeSegmentState extends State<_ThemeSegment> {
  @override
  void initState() {
    super.initState();
    widget.store.notifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    widget.store.notifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final current = widget.store.notifier.value;
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _chip(l10n.themeModeFollowSystem, ThemeMode.system, current),
        const SizedBox(width: 8),
        _chip(l10n.themeModeLight, ThemeMode.light, current),
        const SizedBox(width: 8),
        _chip(l10n.themeModeDark, ThemeMode.dark, current),
      ],
    );
  }

  Widget _chip(String label, ThemeMode mode, ThemeMode current) {
    final selected = current == mode;
    final theme = Theme.of(context);
    final colors = context.appColors;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        widget.store.setTheme(mode);
        Analytics.track(AnalyticsEvents.settingChanged, {
          'key': 'theme_mode',
          'value': mode.name,
        });
      },
      showCheckmark: false,
      labelStyle: theme.textTheme.bodySmall?.copyWith(
        color: selected ? theme.colorScheme.onPrimary : colors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }
}

String _localizedColorThemeName(AppLocalizations l10n, AppColorTheme preset) {
  switch (preset.id) {
    case 'emerald':
      return l10n.settingsColorThemeEmerald;
    case 'ocean':
      return l10n.settingsColorThemeOcean;
    case 'sunset':
      return l10n.settingsColorThemeSunset;
    case 'lavender':
      return l10n.settingsColorThemeLavender;
    case 'rose':
      return l10n.settingsColorThemeRose;
    case 'graphite':
      return l10n.settingsColorThemeGraphite;
    default:
      return l10n.settingsColorThemeEmerald;
  }
}

class _ColorThemePicker extends StatefulWidget {
  const _ColorThemePicker({required this.store});

  final ColorThemeStore store;

  @override
  State<_ColorThemePicker> createState() => _ColorThemePickerState();
}

class _ColorThemePickerState extends State<_ColorThemePicker> {
  @override
  void initState() {
    super.initState();
    widget.store.notifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = widget.store.notifier.value;
    final theme = Theme.of(context);
    final colors = context.appColors;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: 10,
      children: AppColorTheme.presets.map((preset) {
        final selected = current.id == preset.id;
        return GestureDetector(
          onTap: () {
            widget.store.setTheme(preset);
            Analytics.track(AnalyticsEvents.settingChanged, {
              'key': 'color_theme',
              'value': preset.id,
            });
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppSize.settingsSwatch,
                height: AppSize.settingsSwatch,
                decoration: BoxDecoration(
                  color: preset.accent,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 2.5,
                        )
                      : null,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: preset.accent.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: selected
                    ? const Icon(
                        LucideIcons.check,
                        color: Colors.white,
                        size: 20,
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _localizedColorThemeName(l10n, preset),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected ? preset.accent : colors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
