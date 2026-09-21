import '../ui/product_scaffold.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/webdav.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/pending_files_provider.dart';
import '../providers/webdav_provider.dart';
import '../services/webdav_credential_store.dart';
import '../services/webdav_cstcloud.dart';
import '../services/webdav_session.dart';
import '../services/webdav_transfer_service.dart';
import '../ui/app_ui.dart';
import '../utils/toast.dart';
import '../widgets/pending_files_bar.dart';
import '../widgets/webdav_transfer_progress_banner.dart';
import 'webdav/webdav_browsable_tab.dart';
import 'webdav_files_tab.dart';
import 'webdav_recent_favorites_tab.dart';
import 'webdav_connection_screen.dart';
import 'webdav_transfer_list_screen.dart';

class WebDavShellScreen extends ConsumerStatefulWidget {
  final WebDavConnectionSummary connection;
  final bool embedded;
  final VoidCallback? onBack;

  const WebDavShellScreen({
    super.key,
    required this.connection,
    this.embedded = false,
    this.onBack,
  });

  @override
  ConsumerState<WebDavShellScreen> createState() => _WebDavShellScreenState();
}

class _WebDavShellScreenState extends ConsumerState<WebDavShellScreen>
    with WidgetsBindingObserver {
  WebDavClient? _client;
  bool _loading = true;
  String? _error;
  int _tabIndex = 0;
  bool _selectionMode = false;
  int _selectedCount = 0;
  bool _searchVisible = false;
  final _filesTabKey = GlobalKey<WebDavFilesTabState>();
  final _recentTabKey = GlobalKey<WebDavVirtualEntryTabState>();
  final _favoritesTabKey = GlobalKey<WebDavVirtualEntryTabState>();
  String _currentPath = '';
  int _initGeneration = 0;

  bool get _showOutboxButton =>
      !_selectionMode &&
      !cstCloudWebDavBlocksGeneralUpload(widget.connection.baseUrl);

  WebDavBrowsableTabController? _activeTabController() {
    return switch (_tabIndex) {
      0 => _filesTabKey.currentState,
      1 => _recentTabKey.currentState,
      2 => _favoritesTabKey.currentState,
      _ => null,
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapPendingFiles());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reloadPendingFiles());
    }
  }

  Future<void> _bootstrapPendingFiles() async {
    final dropped = await ref.read(pendingFilesProvider.notifier).bootstrap();
    if (!mounted) return;
    if (dropped > 0) {
      AppToast.show(
        context,
        message: AppLocalizations.of(context).chatScreenPendingFilesMissing,
      );
    }
  }

  Future<void> _reloadPendingFiles() async {
    final dropped = await ref
        .read(pendingFilesProvider.notifier)
        .reloadFromStore();
    if (!mounted) return;
    if (dropped > 0) {
      AppToast.show(
        context,
        message: AppLocalizations.of(context).chatScreenPendingFilesMissing,
      );
    }
  }

  Future<void> _init() async {
    final generation = ++_initGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });

    final memoryCreds = WebDavCredentialStore.instance.getFromMemory(
      widget.connection.id,
    );
    if (memoryCreds != null && !cstCloudNeedsCredentialRefresh(memoryCreds)) {
      _client = WebDavClient(memoryCreds);
      if (mounted && generation == _initGeneration) {
        setState(() => _loading = false);
      }
      unawaited(_restoreTransferSnapshots(generation));
      return;
    }

    try {
      final creds = await resolveWebDavCredentials(widget.connection.id);
      if (!mounted || generation != _initGeneration) return;
      _client = WebDavClient(creds);
      if (!mounted || generation != _initGeneration) return;
      setState(() => _loading = false);
      unawaited(_restoreTransferSnapshots(generation));
      if (cstCloudWebDavBlocksGeneralUpload(widget.connection.baseUrl)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _initGeneration) return;
          AppToast.show(
            context,
            message: AppLocalizations.of(context).webdavCstCloudReadOnlyToast,
          );
        });
      }
    } catch (e) {
      if (!mounted || generation != _initGeneration) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _restoreTransferSnapshots(int generation) async {
    await WebDavTransferService.instance.restorePersistedSnapshots(
      widget.connection.id,
    );
    if (!mounted || generation != _initGeneration) return;
  }

  void _onTabSelected(int index) {
    if (index != _tabIndex) {
      _filesTabKey.currentState?.exitSelectionMode();
      _recentTabKey.currentState?.exitSelectionMode();
      _favoritesTabKey.currentState?.exitSelectionMode();
      for (final tab in <WebDavBrowsableTabController?>[
        _filesTabKey.currentState,
        _recentTabKey.currentState,
        _favoritesTabKey.currentState,
      ]) {
        if (tab != null && tab.isSearchVisible) {
          tab.toggleSearch();
        }
      }
    }
    setState(() {
      _tabIndex = index;
      _selectionMode = false;
      _selectedCount = 0;
      _searchVisible = false;
    });
    final connectionId = widget.connection.id;
    if (index == 1) {
      ref.invalidate(webDavRecentProvider(connectionId));
      _recentTabKey.currentState?.refreshEntries();
    } else if (index == 2) {
      ref.invalidate(webDavFavoritesProvider(connectionId));
      _favoritesTabKey.currentState?.refreshEntries();
    }
  }

  void _onTabSelectionChanged(bool selectionMode, int selectedCount) {
    if (_selectionMode == selectionMode && _selectedCount == selectedCount) {
      return;
    }
    setState(() {
      _selectionMode = selectionMode;
      _selectedCount = selectedCount;
    });
  }

  void _onTabSearchVisibilityChanged(bool visible) {
    if (_searchVisible == visible) return;
    setState(() => _searchVisible = visible);
  }

  void _toggleActiveTabSearch() {
    _activeTabController()?.toggleSearch();
  }

  void _exitActiveTabSelectionMode() {
    _activeTabController()?.exitSelectionMode();
  }

  void _switchToFilesTab({String? path}) {
    setState(() => _tabIndex = 0);
    if (path != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _filesTabKey.currentState?.navigateToPath(path);
      });
    }
  }

  void _openTransferList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebDavTransferListScreen(connection: widget.connection),
      ),
    );
  }

  Color _contentBackground(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  void _openSettings() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            WebDavConnectionScreen(connectionId: widget.connection.id),
      ),
    );
    if (ok == true && mounted) {
      await ref.read(webDavConnectionsProvider.notifier).refresh();
      await _init();
    }
  }

  String _uploadTargetLabel(AppLocalizations l10n) {
    final relativePath = _filesTabKey.currentState?.currentRelativePath ?? '';
    if (relativePath.isEmpty) {
      return l10n.webdavOutboxUploadTarget(widget.connection.name);
    }
    return l10n.webdavOutboxUploadTarget('/$relativePath');
  }

  Future<void> _openOutboxSheet() {
    if (!_showOutboxButton) return Future.value();
    final l10n = AppLocalizations.of(context);
    return showPendingOutboxSheet(
      context,
      showAddFiles: true,
      primaryAction: PendingOutboxPrimaryAction(
        label: l10n.webdavOutboxUpload,
        icon: LucideIcons.upload,
        destinationHint: _uploadTargetLabel(l10n),
        onExecute: (entries, layout) async {
          final filesTab = _filesTabKey.currentState;
          if (filesTab == null) return;
          if (cstCloudWebDavBlocksGeneralUpload(widget.connection.baseUrl)) {
            if (!mounted) return;
            AppToast.show(
              context,
              message: l10n.webdavCstCloudUploadNotSupported,
            );
            return;
          }
          try {
            final result = await filesTab.queuePlatformFileUploads(
              entries,
              layout: layout,
            );
            if (!mounted) return;
            if (result.skipped > 0) {
              AppToast.show(
                context,
                message: l10n.fmPendingDispatchPartialSkipped(result.skipped),
              );
            }
            if (result.started > 0) {
              AppToast.show(
                context,
                message: l10n.webdavTransferQueued(result.started),
              );
            }
          } catch (e) {
            if (!mounted) return;
            AppToast.show(context, message: l10n.webdavUploadFailed('$e'));
          }
        },
      ),
    );
  }

  Widget _buildWebDavTabs(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.appColors;
    final pendingCount = ref.watch(pendingFilesProvider).length;
    final labels = [
      l10n.webdavTabFiles,
      l10n.webdavTabRecent,
      l10n.webdavTabFavorites,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(labels.length, (index) {
                  final selected = _tabIndex == index;
                  return Semantics(
                    selected: selected,
                    child: TextButton(
                      onPressed: () => _onTabSelected(index),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 44),
                        foregroundColor: selected
                            ? Theme.of(context).colorScheme.primary
                            : colors.textSecondary,
                        backgroundColor: selected ? colors.accentSoft : null,
                      ),
                      child: Text(labels[index]),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Badge(
            isLabelVisible: pendingCount > 0,
            label: Text('$pendingCount'),
            child: FilledButton.icon(
              onPressed: _showOutboxButton ? _openOutboxSheet : null,
              icon: const Icon(LucideIcons.upload, size: 16),
              label: Text(l10n.webdavTabUpload),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return _wrapShell(
        context,
        AppBar(
          automaticallyImplyLeading: false,
          leading: _buildBackButton(context),
          title: Text(widget.connection.name),
        ),
        const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _client == null) {
      return _wrapShell(
        context,
        AppBar(
          automaticallyImplyLeading: false,
          leading: _buildBackButton(context),
          title: Text(widget.connection.name),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Error', textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: _init,
                  child: Text(l10n.connectionBarRefreshOnlineStatus),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final client = _client!;
    final transferUi = ref.watch(
      webDavTransferUiProvider(widget.connection.id),
    );
    final activeTransfers = transferUi.activeCount;
    final contentBg = _contentBackground(context);

    final body = ColoredBox(
      color: contentBg,
      child: Column(
        children: [
          _buildWebDavTabs(context),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IndexedStack(
                  index: _tabIndex,
                  children: [
                    WebDavFilesTab(
                      key: _filesTabKey,
                      connection: widget.connection,
                      client: client,
                      initialPath: _currentPath,
                      onPathChanged: (p) => _currentPath = p,
                      onSelectionChanged: _onTabSelectionChanged,
                      onSearchVisibilityChanged: _onTabSearchVisibilityChanged,
                    ),
                    WebDavRecentTab(
                      key: _recentTabKey,
                      connection: widget.connection,
                      client: client,
                      onOpenFolder: (path) => _switchToFilesTab(path: path),
                      onSelectionChanged: _onTabSelectionChanged,
                      onSearchVisibilityChanged: _onTabSearchVisibilityChanged,
                    ),
                    WebDavFavoritesTab(
                      key: _favoritesTabKey,
                      connection: widget.connection,
                      client: client,
                      onOpenFolder: (path) => _switchToFilesTab(path: path),
                      onSelectionChanged: _onTabSelectionChanged,
                      onSearchVisibilityChanged: _onTabSearchVisibilityChanged,
                    ),
                  ],
                ),
                Positioned(
                  right: AppSpacing.md,
                  bottom: AppSpacing.sm,
                  child: WebDavTransferProgressBanner(
                    connectionId: widget.connection.id,
                    onTap: _openTransferList,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: !_selectionMode && widget.onBack == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode) {
          _exitActiveTabSelectionMode();
          return;
        }
        if (!didPop && widget.onBack != null) {
          widget.onBack!();
        }
      },
      child: _wrapShell(
        context,
        AppBar(
          automaticallyImplyLeading: false,
          leading: _buildBackButton(context),
          title: Text(_appBarTitle(l10n)),
          actions: _buildAppBarActions(l10n, activeTransfers),
        ),
        body,
      ),
    );
  }

  Widget? _buildBackButton(BuildContext context) {
    if (widget.embedded || widget.onBack == null) return null;
    return IconButton(
      icon: const Icon(LucideIcons.arrowLeft),
      onPressed: widget.onBack,
      tooltip: AppLocalizations.of(context).chatTooltipBackDeviceList,
    );
  }

  Widget _wrapShell(
    BuildContext context,
    PreferredSizeWidget appBar,
    Widget body,
  ) {
    final contentBg = _contentBackground(context);
    return ColoredBox(
      color: contentBg,
      child: ProductScaffold(
        section: ProductSection.files,
        filesLocation: '/files/cloud',
        embedded: widget.embedded,
        primary: !widget.embedded,
        resizeToAvoidBottomInset: false,
        backgroundColor: contentBg,
        appBar: appBar,
        body: body,
      ),
    );
  }

  String _appBarTitle(AppLocalizations l10n) {
    if (_selectionMode) {
      return l10n.webdavSelectedCount(_selectedCount);
    }
    if (_tabIndex == 0) {
      return widget.connection.name;
    }
    return _tabTitle(l10n);
  }

  List<Widget> _buildAppBarActions(AppLocalizations l10n, int activeTransfers) {
    if (_selectionMode) {
      final tab = _activeTabController();
      final hasSelection = _selectedCount > 0;
      final colors = context.appColors;

      return [
        IconButton(
          icon: const Icon(LucideIcons.download),
          onPressed: hasSelection ? () => tab?.downloadSelected() : null,
          tooltip: l10n.webdavActionDownload,
        ),
        IconButton(
          icon: const Icon(LucideIcons.share2),
          onPressed: hasSelection ? () => tab?.shareSelected() : null,
          tooltip: l10n.webdavActionShare,
        ),
        IconButton(
          icon: Icon(LucideIcons.trash2, color: colors.danger),
          onPressed: hasSelection ? () => tab?.deleteSelected() : null,
          tooltip: l10n.webdavActionDelete,
        ),
        IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: _exitActiveTabSelectionMode,
          tooltip: l10n.cancel,
        ),
      ];
    }

    return [
      IconButton(
        icon: Icon(_searchVisible ? LucideIcons.searchX : LucideIcons.search),
        onPressed: _toggleActiveTabSearch,
        tooltip: _searchVisible
            ? l10n.fmSearchCloseTooltip
            : l10n.fmSearchTooltip,
      ),
      IconButton(
        icon: activeTransfers > 0
            ? Badge(
                label: Text('$activeTransfers'),
                child: const Icon(LucideIcons.activity),
              )
            : const Icon(LucideIcons.activity),
        onPressed: _openTransferList,
        tooltip: l10n.webdavTransferList,
      ),
      IconButton(
        icon: const Icon(LucideIcons.settings),
        onPressed: _openSettings,
        tooltip: l10n.webdavEditConnection,
      ),
    ];
  }

  String _tabTitle(AppLocalizations l10n) {
    return switch (_tabIndex) {
      1 => l10n.webdavTabRecent,
      2 => l10n.webdavTabFavorites,
      _ => widget.connection.name,
    };
  }
}
