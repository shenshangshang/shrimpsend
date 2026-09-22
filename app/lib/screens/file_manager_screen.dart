import '../ui/product_scaffold.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/pending_file_entry.dart';
import '../services/desktop_file_clipboard.dart';
import '../services/file_export_service.dart';
import '../services/file_store.dart';
import '../providers/pending_files_provider.dart';
import '../services/receive_dir_resolver.dart';
import '../services/received_file_dao.dart';
import '../services/save_folder_listing_service.dart';
import '../services/visible_export_target.dart';
import '../ui/app_ui.dart';
import '../widgets/desktop_paste_shortcuts.dart';
import '../utils/file_utils.dart';
import '../utils/open_directory.dart';
import '../utils/runtime_platform.dart';
import '../utils/open_received_file.dart';
import '../utils/received_file_actions.dart';
import '../utils/save_as_feedback.dart';
import '../utils/toast.dart';
import '../widgets/app_confirm_dialog.dart';
import '../widgets/desktop_file_drag_source.dart';
import '../widgets/file_icon_widget.dart';
import '../widgets/received_file_info_dialog.dart';
import 'settings_screen.dart';

class FileManagerScreen extends StatefulWidget {
  final Future<bool> Function(List<PlatformFile>)? onAddToPending;

  /// When true (e.g. mobile home tab), hide back [leading] — no route to pop.
  final bool embedded;
  final String initialView;

  /// Incremented by the parent each time the embedded files tab is selected; triggers a silent refresh.
  final int embeddedFileTabActivation;

  const FileManagerScreen({
    super.key,
    this.onAddToPending,
    this.embedded = false,
    this.initialView = '/files',
    this.embeddedFileTabActivation = 0,
  });

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 50;
  static const _prefSortBy = 'file_manager_sort_by';

  late TabController _tabController;
  String _view = '/files';
  String _typeFilter = 'all';
  Set<String> _favorites = {};
  List<ReceivedFileInfo> _favoriteFiles = [];
  bool _favoritesLoading = false;
  int _fileQueryRevision = 0;

  List<ReceivedFileInfo> _filterFiles(
    List<ReceivedFileInfo> files,
  ) => files.where((file) {
    if (_searchQuery.isNotEmpty &&
        !file.displayName.toLowerCase().contains(_searchQuery.toLowerCase()))
      return false;
    if (_typeFilter == 'document')
      return [
        FileCategory.document,
        FileCategory.pdf,
        FileCategory.code,
      ].contains(file.category);
    return _typeFilter == 'all' || file.category.name == _typeFilter;
  }).toList()..sort((a, b) => _displayTimeFor(b).compareTo(_displayTimeFor(a)));

  void _selectView(String value) {
    setState(() {
      _view = value;
      _selectedFiles.clear();
      _isSelectionMode = false;
      _searchQuery = '';
      _saveFolderSearchQuery = '';
      _searchController.clear();
    });
    _tabController.index = value == '/files' ? 0 : 1;
    if (value == '/files/favorites') {
      unawaited(_loadFavorites());
    } else if (value == '/files/recent') {
      unawaited(_loadFiles());
    } else {
      unawaited(_loadSaveFolderFiles());
    }
  }

  Future<void> _loadFavorites() async {
    if (mounted) setState(() => _favoritesLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList('product.favoriteFiles') ?? [];
      final found = <ReceivedFileInfo>[];
      for (final path in paths) {
        final known = [
          ..._saveFolderFiles,
          ..._files,
        ].where((file) => file.path == path).firstOrNull;
        if (known != null) {
          found.add(known);
          continue;
        }
        FileStat stat;
        try {
          stat = await FileStat.stat(path);
        } on FileSystemException {
          continue;
        }
        if (stat.type != FileSystemEntityType.file) continue;
        final name = path.split(Platform.pathSeparator).last;
        found.add(
          ReceivedFileInfo(
            messageId: 'favorite:$path',
            path: path,
            displayName: name,
            protocol: 'local',
            size: stat.size,
            modified: stat.modified,
            createdAt: stat.modified,
            category: getFileCategory(name),
            exportStatus: ExportStatus.legacy,
          ),
        );
      }
      found.sort((a, b) => b.modified.compareTo(a.modified));
      if (mounted)
        setState(() {
          _favorites = paths.toSet();
          _favoriteFiles = found;
        });
    } catch (_) {
      if (mounted)
        AppToast.show(
          context,
          message: Localizations.localeOf(context).languageCode == 'zh'
              ? '无法读取收藏，请重试'
              : 'Unable to load favorites. Try again.',
        );
    } finally {
      if (mounted) setState(() => _favoritesLoading = false);
    }
  }

  Future<void> _toggleFavorite(ReceivedFileInfo file) async {
    final next = Set<String>.from(_favorites);
    if (!next.add(file.path)) next.remove(file.path);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('product.favoriteFiles', next.toList());
      if (mounted)
        setState(() {
          _favorites = next;
          if (!next.contains(file.path)) {
            _favoriteFiles.removeWhere((item) => item.path == file.path);
            _selectedFiles.remove(file.path);
          }
        });
      if (_view == '/files/favorites') await _loadFavorites();
    } catch (_) {
      if (mounted)
        AppToast.show(
          context,
          message: Localizations.localeOf(context).languageCode == 'zh'
              ? '未能保存收藏，请重试'
              : 'Unable to save favorite. Try again.',
        );
    }
  }

  List<ReceivedFileInfo> _files = [];
  List<ReceivedFileInfo> _saveFolderFiles = [];
  SaveFolderAccessError? _saveFolderError;
  String? _saveFolderDisplayPath;
  String? _saveFolderDisplayLabel;
  String _saveFolderSearchQuery = '';
  ReceivedFileSortBy _sortBy = ReceivedFileSortBy.createdAt;
  bool _loading = true;
  bool _saveFolderLoading = false;
  final bool _categoryView = false;
  bool _hasMore = true;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String? _hoveredFilePath;
  bool _isSelectionMode = false;
  final Set<String> _selectedFiles = {};
  Timer? _indexChangeDebounce;

  bool get _isSearching => _searchQuery.isNotEmpty;

  bool get _isSaveFolderTab => _tabController.index == 0;

  List<ReceivedFileInfo> get _activeFiles => _filterFiles(
    _view == '/files/favorites'
        ? _favoriteFiles
        : _isSaveFolderTab
        ? _saveFolderFiles
        : _files,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _view = widget.initialView;
    _tabController.index = _view == '/files' ? 0 : 1;
    _tabController.addListener(_onMainTabChanged);
    unawaited(_loadFavorites());
    _scrollController.addListener(_onScroll);
    _loadReceiveDirPath();
    unawaited(_loadSaveFolderDisplayInfo());
    unawaited(_loadSaveFolderFiles());
    unawaited(_loadSortPreference().then((_) => _loadFiles()));
    ReceivedFileDao.addChangedListener(_onIndexChanged);
    FileStore.addReceiveDirChangedListener(_onReceiveDirChanged);
  }

  void _onMainTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_isSelectionMode) {
      _exitSelectionMode();
    }
    if (_isSaveFolderTab) {
      unawaited(_loadSaveFolderFiles());
    }
    if (mounted) setState(() {});
  }

  /// Coalesce bursts of file-receive events into a single silent refresh so
  /// rapid multi-file transfers do not thrash the list.
  void _onIndexChanged() {
    if (!mounted) return;
    _indexChangeDebounce?.cancel();
    _indexChangeDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _silentRefreshFiles();
      unawaited(_silentRefreshSaveFolder());
    });
  }

  /// Receive root just changed in settings — refresh the displayed dir path
  /// and reload the listing.
  void _onReceiveDirChanged() {
    if (!mounted) return;
    unawaited(_loadReceiveDirPath(invalidateDirCache: true));
    unawaited(_loadSaveFolderDisplayInfo(forceRefresh: true));
    _onIndexChanged();
    if (_isSaveFolderTab) {
      unawaited(_silentRefreshSaveFolder());
    }
  }

  @override
  void didUpdateWidget(FileManagerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.embedded &&
        widget.embeddedFileTabActivation !=
            oldWidget.embeddedFileTabActivation &&
        widget.embeddedFileTabActivation > 0) {
      _silentRefreshFiles();
      if (_isSaveFolderTab) {
        unawaited(_silentRefreshSaveFolder());
      }
    }
  }

  Future<void> _loadReceiveDirPath({bool invalidateDirCache = false}) async {
    if (invalidateDirCache) FileStore.invalidateReceiveDirCache();
  }

  /// Reload listing without clearing the list or showing the full-screen loading state.
  Future<void> _silentRefreshFiles() async {
    if (!mounted) return;

    try {
      await _loadReceiveDirPath(invalidateDirCache: true);

      if (_categoryView) {
        final files = await _queryAllForCategoryView();
        if (mounted) {
          setState(() {
            _files = files;
            _hasMore = false;
          });
        }
      } else if (_isSearching) {
        await _performSearch(_searchQuery);
      } else {
        final files = await _queryPaged(0, _pageSize);
        if (mounted) {
          setState(() {
            _files = files;
            _hasMore = files.length == _pageSize;
          });
        }
      }
    } catch (e, st) {
      debugPrint('FileManagerScreen._silentRefreshFiles failed: $e\n$st');
      if (mounted) {
        AppToast.show(
          context,
          message: AppLocalizations.of(context).fmRefreshFailed,
        );
      }
    }
  }

  Future<void> _loadSortPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefSortBy);
      if (!mounted) return;
      if (raw == ReceivedFileSortBy.modified.name) {
        setState(() => _sortBy = ReceivedFileSortBy.modified);
      } else {
        setState(() => _sortBy = ReceivedFileSortBy.createdAt);
      }
    } catch (_) {}
  }

  Future<void> _persistSortPreference(ReceivedFileSortBy sortBy) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefSortBy, sortBy.name);
    } catch (_) {}
  }

  Future<void> _onSortByChanged(ReceivedFileSortBy sortBy) async {
    if (_sortBy == sortBy) return;
    setState(() => _sortBy = sortBy);
    await _persistSortPreference(sortBy);
    if (_categoryView) {
      await _loadAllForCategory();
    } else if (_isSearching) {
      await _performSearch(_searchQuery);
    } else {
      await _loadFiles();
    }
  }

  DateTime _displayTimeFor(ReceivedFileInfo file) =>
      _sortBy == ReceivedFileSortBy.modified ? file.modified : file.createdAt;

  Future<List<ReceivedFileInfo>> _queryPaged(int offset, int limit) async {
    final rows = await ReceivedFileDao.instance.listPaged(
      offset: offset,
      limit: limit,
      sortBy: _sortBy,
      categories: _typeFilter == 'all'
          ? null
          : _typeFilter == 'document'
          ? ['document', 'pdf', 'code']
          : [_typeFilter],
      query: _searchQuery,
      cacheTabOnly: false,
    );
    return rows.map((r) => r.toInfo()).toList();
  }

  /// Used by the category view (small datasets — first page is enough; we
  /// load up to 1000 entries to keep grouping responsive without OOM).
  Future<List<ReceivedFileInfo>> _queryAllForCategoryView() async {
    final rows = await ReceivedFileDao.instance.listPaged(
      offset: 0,
      limit: 1000,
      sortBy: _sortBy,
      cacheTabOnly: false,
    );
    return rows.map((r) => r.toInfo()).toList();
  }

  /// Run reconcile in the background; never blocks the UI thread.
  Future<void> _reconcileIndex() async {
    try {
      final root = await FileStore.getCacheDir();
      await ReceivedFileDao.instance.reconcileWithRoot(root);
    } catch (e, st) {
      debugPrint('FileManagerScreen._reconcileIndex failed: $e\n$st');
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onMainTabChanged);
    _tabController.dispose();
    _indexChangeDebounce?.cancel();
    ReceivedFileDao.removeChangedListener(_onIndexChanged);
    FileStore.removeReceiveDirChangedListener(_onReceiveDirChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_view != '/files/recent') return;
    if (!_categoryView &&
        _hasMore &&
        !_loadingMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMoreFiles();
    }
  }

  /// [showBlockingLoading] — false for pull-to-refresh (keeps list visible; only the indicator shows progress).
  Future<void> _loadFiles({bool showBlockingLoading = true}) async {
    if (!mounted) return;
    if (showBlockingLoading) {
      setState(() => _loading = true);
    }
    final revision = ++_fileQueryRevision;
    try {
      final files = await _queryPaged(0, _pageSize);
      if (!mounted || revision != _fileQueryRevision) return;
      setState(() {
        _files = files;
        _hasMore = files.length == _pageSize;
      });
    } catch (e, st) {
      debugPrint('FileManagerScreen._loadFiles failed: $e\n$st');
      if (mounted) {
        AppToast.show(
          context,
          message: AppLocalizations.of(context).fmListLoadFailed,
        );
      }
    } finally {
      if (showBlockingLoading && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Reconcile the index against the disk, then reload the current view.
  Future<void> _pullRefresh() async {
    if (_view == '/files/favorites') {
      await _loadFavorites();
      return;
    }
    if (_isSaveFolderTab) {
      await _loadSaveFolderFiles(showBlockingLoading: false);
      return;
    }
    await _loadReceiveDirPath(invalidateDirCache: true);
    await _reconcileIndex();
    if (_categoryView) {
      await _loadAllForCategory(showBlockingLoading: false);
    } else if (_isSearching) {
      await _performSearch(_searchQuery);
    } else {
      await _loadFiles(showBlockingLoading: false);
    }
  }

  Future<void> _loadSaveFolderFiles({bool showBlockingLoading = true}) async {
    if (!mounted) return;
    if (showBlockingLoading) {
      setState(() => _saveFolderLoading = true);
    }
    try {
      final result = await SaveFolderListingService.list();
      if (!mounted) return;
      setState(() {
        _saveFolderFiles = result.files
            .map(SaveFolderListingService.toReceivedFileInfo)
            .toList();
        _saveFolderError = result.error;
        _saveFolderDisplayPath = result.displayPath;
        _saveFolderDisplayLabel = result.displayLabel;
      });
    } catch (e, st) {
      debugPrint('FileManagerScreen._loadSaveFolderFiles failed: $e\n$st');
      if (mounted) {
        AppToast.show(
          context,
          message: AppLocalizations.of(context).fmListLoadFailed,
        );
      }
    } finally {
      if (showBlockingLoading && mounted) {
        setState(() => _saveFolderLoading = false);
      }
    }
  }

  Future<void> _silentRefreshSaveFolder() async {
    if (!mounted) return;
    await _loadSaveFolderFiles(showBlockingLoading: false);
  }

  String _saveFolderErrorMessage(AppLocalizations l10n) {
    final error = _saveFolderError;
    if (error == null) return l10n.fmSaveFolderNotAccessible;
    switch (error.kind) {
      case SaveFolderAccessErrorKind.notConfigured:
        return l10n.fmSaveFolderNotConfigured;
      case SaveFolderAccessErrorKind.permissionDenied:
        return l10n.fmSaveFolderPermissionDenied;
      case SaveFolderAccessErrorKind.notAccessible:
        return l10n.fmSaveFolderNotAccessible;
      case SaveFolderAccessErrorKind.ioError:
        final detail = error.detail?.trim();
        if (detail != null && detail.isNotEmpty) {
          return l10n.fmSaveFolderErrorDetail(detail);
        }
        return l10n.fmSaveFolderNotAccessible;
    }
  }

  Future<void> _loadMoreFiles() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _queryPaged(_files.length, _pageSize);
      if (!mounted) return;
      setState(() {
        _files.addAll(more);
        _hasMore = more.length == _pageSize;
      });
    } catch (e, st) {
      debugPrint('FileManagerScreen._loadMoreFiles failed: $e\n$st');
      if (mounted) {
        AppToast.show(
          context,
          message: AppLocalizations.of(context).fmLoadMoreFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _loadAllForCategory({bool showBlockingLoading = true}) async {
    if (!mounted) return;
    if (showBlockingLoading) {
      setState(() => _loading = true);
    }
    try {
      final files = await _queryAllForCategoryView();
      if (!mounted) return;
      setState(() {
        _files = files;
        _hasMore = false;
      });
    } catch (e, st) {
      debugPrint('FileManagerScreen._loadAllForCategory failed: $e\n$st');
      if (mounted) {
        AppToast.show(
          context,
          message: AppLocalizations.of(context).fmListLoadFailed,
        );
      }
    } finally {
      if (showBlockingLoading && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _selectedFiles.clear();
      _isSelectionMode = false;
    });
    if (_view == '/files/favorites') return;
    if (_isSaveFolderTab) {
      setState(() => _saveFolderSearchQuery = query);
      return;
    }
    if (query.isEmpty) {
      if (_categoryView) {
        _loadAllForCategory();
      } else {
        _loadFiles();
      }
    } else {
      _performSearch(query);
    }
  }

  Future<void> _performSearch(String query) async {
    final revision = ++_fileQueryRevision;
    try {
      final rows = await ReceivedFileDao.instance.listPaged(
        offset: 0,
        limit: 1000,
        query: query,
        categories: _typeFilter == 'all'
            ? null
            : _typeFilter == 'document'
            ? ['document', 'pdf', 'code']
            : [_typeFilter],
        sortBy: _sortBy,
        cacheTabOnly: false,
      );
      final results = rows.map((r) => r.toInfo()).toList();
      if (!mounted) return;
      if (_searchQuery == query && revision == _fileQueryRevision) {
        setState(() {
          _files = results;
          _hasMore = false;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('FileManagerScreen._performSearch failed: $e\n$st');
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.show(
        context,
        message: AppLocalizations.of(context).fmSearchFailed,
      );
    }
  }

  bool get _isMobile => RuntimePlatform.isMobile;

  EdgeInsets _listVerticalPadding(BuildContext context) {
    return EdgeInsets.only(
      top: AppSpacing.xs,
      bottom: AppSpacing.xs + (widget.embedded ? 0.0 : 0),
    );
  }

  Future<void> _deleteFile(ReceivedFileInfo file) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppConfirmDialog.show(
      context,
      title: l10n.fmDeleteTitle,
      content: l10n.fmDeleteConfirmOne(file.displayName),
      confirmLabel: l10n.fmDeleteConfirm,
      isDanger: true,
      icon: LucideIcons.trash2,
    );
    if (confirmed) {
      final ok = await _removeFile(file);
      await _reloadAfterDelete();
      if (!ok && mounted) {
        AppToast.show(context, message: l10n.fmDeleteFailed);
      }
    }
  }

  Future<void> _reloadAfterDelete() async {
    if (_isSaveFolderTab) {
      await _loadSaveFolderFiles(showBlockingLoading: false);
      return;
    }
    if (_categoryView) {
      await _pullRefresh();
    } else if (_isSearching) {
      await _performSearch(_searchQuery);
    } else {
      await _loadFiles();
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    final count = _selectedFiles.length;
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppConfirmDialog.show(
      context,
      title: l10n.fmDeleteTitle,
      content: l10n.fmDeleteConfirmMany(count),
      confirmLabel: l10n.fmDeleteConfirm,
      isDanger: true,
      icon: LucideIcons.trash2,
    );
    if (!confirmed) return;

    final deletedPaths = Set<String>.from(_selectedFiles);
    final byPath = {for (final f in _activeFiles) f.path: f};
    var anyFailed = false;
    for (final path in deletedPaths) {
      final f = byPath[path];
      if (f != null) {
        if (!await _removeFile(f)) anyFailed = true;
      } else {
        if (!await FileStore.deleteFile(path, useTrash: true)) anyFailed = true;
      }
    }

    setState(() {
      _selectedFiles.removeWhere((path) => deletedPaths.contains(path));
    });

    if (_isSaveFolderTab) {
      await _loadSaveFolderFiles(showBlockingLoading: false);
    } else if (_categoryView) {
      await _pullRefresh();
    } else if (_isSearching) {
      await _performSearch(_searchQuery);
    } else {
      await _loadFiles();
    }

    if (anyFailed && mounted) {
      AppToast.show(context, message: l10n.fmDeleteFailed);
    }
  }

  /// Deletes a file's on-disk copy. User-initiated, so desktop platforms move
  /// it to the system recycle bin. Returns true on success.
  Future<bool> _removeFile(ReceivedFileInfo file) async {
    if (SaveFolderListingService.isSaveFolderEntry(file)) {
      return SaveFolderListingService.deleteEntry(file, useTrash: true);
    }
    final ok = await FileStore.deleteFile(file.path, useTrash: true);
    try {
      await ReceivedFileDao.instance.removeByMessageId(file.messageId);
    } catch (_) {}
    return ok;
  }

  void _openFile(ReceivedFileInfo file) {
    unawaited(_openFileResolved(file));
  }

  ReceivedFilePreviewCallbacks _previewCallbacksFor(ReceivedFileInfo file) {
    return ReceivedFilePreviewCallbacks(
      onEnterMultiSelect: () {
        setState(() {
          _isSelectionMode = true;
          _selectedFiles.add(file.path);
        });
      },
      onAddToPending: _addFilesToPending,
      onDeleted: () => unawaited(_reloadAfterDelete()),
    );
  }

  Future<void> _openFileResolved(ReceivedFileInfo file) async {
    if (SaveFolderListingService.isSaveFolderEntry(file) &&
        file.path.startsWith('content://')) {
      final localPath = await SaveFolderListingService.resolveLocalPath(file);
      if (!mounted) return;
      if (localPath == null || localPath.isEmpty) {
        AppToast.show(
          context,
          message: AppLocalizations.of(context).fmPreviewUnavailableTitle,
        );
        return;
      }
      final previewFile = ReceivedFileInfo(
        messageId: file.messageId,
        path: localPath,
        displayName: file.displayName,
        protocol: file.protocol,
        size: file.size,
        modified: file.modified,
        createdAt: file.createdAt,
        category: file.category,
      );
      await openReceivedFile(
        context,
        previewFile,
        callbacks: _previewCallbacksFor(previewFile),
      );
      return;
    }
    if (!mounted) return;
    await openReceivedFile(
      context,
      file,
      callbacks: _previewCallbacksFor(file),
    );
  }

  Future<void> _shareFile(ReceivedFileInfo file) async {
    final path = await _resolveSharePath(file);
    if (path == null) return;
    await Share.shareXFiles([XFile(path)]);
  }

  Future<void> _shareSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    final xFiles = <XFile>[];
    for (final path in _selectedFiles) {
      final file = _fileByPath(path);
      if (file == null) {
        xFiles.add(XFile(path));
        continue;
      }
      final resolved = await _resolveSharePath(file);
      if (resolved != null) {
        xFiles.add(XFile(resolved));
      }
    }
    if (xFiles.isEmpty) return;
    await Share.shareXFiles(xFiles);
  }

  Future<String?> _resolveSharePath(ReceivedFileInfo file) async {
    if (SaveFolderListingService.isSaveFolderEntry(file) &&
        file.path.startsWith('content://')) {
      return SaveFolderListingService.resolveLocalPath(file);
    }
    return file.path;
  }

  Future<void> _exportFile(ReceivedFileInfo file) async {
    await runSaveFileAs(
      context: context,
      l10n: AppLocalizations.of(context),
      sourcePath: file.path,
      fileName: file.displayName,
    );
  }

  String _exportActionLabel(AppLocalizations l10n) => saveAsActionLabel(l10n);

  Future<bool> _addFilesToPending(List<PlatformFile> platformFiles) async {
    if (platformFiles.isEmpty) return false;

    if (widget.onAddToPending != null) {
      return widget.onAddToPending!(platformFiles);
    }

    if (!mounted) return false;
    final result = await ProviderScope.containerOf(context, listen: false)
        .read(pendingFilesProvider.notifier)
        .add(
          platformFiles
              .map((f) => PendingFileEntry.fromPlatformFile(f))
              .toList(),
        );
    return result.added > 0;
  }

  Future<void> _addToPending(ReceivedFileInfo file) async {
    final l10n = AppLocalizations.of(context);
    final platformFile = PlatformFile(
      name: file.displayName,
      size: file.size,
      path: file.path,
    );
    final ok = await _addFilesToPending([platformFile]);
    if (!mounted) return;
    AppToast.show(
      context,
      message: ok
          ? l10n.fmPendingAddedOne(file.displayName)
          : l10n.fmPendingAddFailed,
    );
  }

  Future<void> _addSelectedToPending() async {
    if (_selectedFiles.isEmpty) return;

    final selectedFiles = _activeFiles
        .where((f) => _selectedFiles.contains(f.path))
        .toList();
    if (selectedFiles.isEmpty) return;

    final platformFiles = selectedFiles
        .map(
          (file) => PlatformFile(
            name: file.displayName,
            size: file.size,
            path: file.path,
          ),
        )
        .toList();

    final ok = await _addFilesToPending(platformFiles);
    if (!mounted) return;
    final count = selectedFiles.length;
    AppToast.show(
      context,
      message: ok
          ? AppLocalizations.of(context).fmPendingAddedMany(count)
          : AppLocalizations.of(context).fmPendingAddFailed,
    );
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedFiles.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedFiles.length == _activeFiles.length) {
        _selectedFiles.clear();
      } else {
        _selectedFiles.clear();
        _selectedFiles.addAll(_activeFiles.map((f) => f.path));
      }
    });
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  List<String> _pathsToCopy() {
    if (_selectedFiles.isNotEmpty) {
      return _selectedFiles.toList();
    }
    final hovered = _hoveredFilePath;
    if (hovered != null) return [hovered];
    return const [];
  }

  Future<void> _copyFilesToClipboard([List<String>? paths]) async {
    final l10n = AppLocalizations.of(context);
    final toCopy = paths ?? _pathsToCopy();
    if (toCopy.isEmpty) {
      AppToast.show(context, message: l10n.fileClipboardNothingToCopy);
      return;
    }
    final resolvedPaths = <String>[];
    for (final path in toCopy) {
      final file = _fileByPath(path);
      if (file != null &&
          SaveFolderListingService.isSaveFolderEntry(file) &&
          file.path.startsWith('content://')) {
        final local = await SaveFolderListingService.resolveLocalPath(file);
        if (local != null && local.isNotEmpty) {
          resolvedPaths.add(local);
        }
      } else {
        resolvedPaths.add(path);
      }
    }
    if (resolvedPaths.isEmpty) {
      if (!mounted) return;
      AppToast.show(context, message: l10n.fileClipboardCopyFailed);
      return;
    }
    final ok = await DesktopFileClipboard.writeFilesToClipboard(resolvedPaths);
    if (!mounted) return;
    AppToast.show(
      context,
      message: ok
          ? l10n.fileClipboardCopied(resolvedPaths.length)
          : l10n.fileClipboardCopyFailed,
    );
  }

  Future<void> _handleDesktopPaste(List<PlatformFile> files) async {
    if (!_isDesktop || files.isEmpty || !mounted) return;

    final ok = await _addFilesToPending(files);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    AppToast.show(
      context,
      message: ok
          ? (widget.onAddToPending != null
                ? (files.length == 1
                      ? l10n.fmPendingAddedOne(files.first.name)
                      : l10n.fmPendingAddedMany(files.length))
                : l10n.fileClipboardPasteAdded)
          : l10n.fmPendingAddFailed,
    );
  }

  ReceivedFileInfo? _fileByPath(String path) {
    for (final file in _activeFiles) {
      if (file.path == path) return file;
    }
    return null;
  }

  Future<void> _revealInFolder(ReceivedFileInfo file) async {
    await revealFileInFileManager(file.path);
  }

  void _showFileInfo(ReceivedFileInfo file) {
    unawaited(showReceivedFileInfoDialog(context, file));
  }

  Future<void> _loadSaveFolderDisplayInfo({bool forceRefresh = false}) async {
    try {
      if (forceRefresh) {
        FileStore.invalidateReceiveDirCache();
      }
      final info = await _resolveSaveFolderDisplayInfo(
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        setState(() {
          _saveFolderDisplayLabel = info.label;
          _saveFolderDisplayPath = info.path;
        });
      }
    } catch (e, st) {
      debugPrint(
        'FileManagerScreen._loadSaveFolderDisplayInfo failed: $e\n$st',
      );
    }
  }

  Future<({String? label, String? path})> _resolveSaveFolderDisplayInfo({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _saveFolderDisplayPath != null &&
        _saveFolderDisplayPath!.isNotEmpty) {
      return (label: _saveFolderDisplayLabel, path: _saveFolderDisplayPath);
    }
    try {
      final target = await FileStore.getVisibleExportTarget();
      final label = target.displayName;
      final safUri = target.safTreeUri?.trim();
      if (safUri != null && safUri.isNotEmpty) {
        return (label: label, path: safUri);
      }
      final posixPath = target.posixPath?.trim();
      if (posixPath != null && posixPath.isNotEmpty) {
        return (label: label, path: posixPath);
      }
      if (target.kind == VisibleExportKind.downloads) {
        final base = await ReceiveDirResolver.getPublicDownloadsBase();
        return (label: label, path: base ?? label);
      }
      return (label: label, path: label);
    } catch (_) {
      return (label: null, path: null);
    }
  }

  void _openSettings() {
    if (widget.embedded) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
      return;
    }
    openProductRoute(context, '/settings');
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 768;
    final title = _view == '/files/favorites'
        ? (zh ? '收藏' : 'Favorites')
        : _view == '/files/recent'
        ? (zh ? '最近使用' : 'Recent files')
        : (zh ? '本机文件' : 'Local files');
    final files = _activeFiles;
    final busy = _isSaveFolderTab
        ? _saveFolderLoading
        : _view == '/files/favorites'
        ? _favoritesLoading
        : _loading;
    final scaffold = ProductScaffold(
      section: ProductSection.files,
      filesLocation: _view,
      embedded: widget.embedded,
      sidebar: ProductFilesSidebar(location: _view, onLocalView: _selectView),
      appBar: AppBar(
        automaticallyImplyLeading: !wide && !widget.embedded,
        toolbarHeight: wide ? 80 : 64,
        titleSpacing: wide ? 28 : 20,
        title: Text(
          _isSelectionMode
              ? l10n.fmSelectedCount(_selectedFiles.length)
              : title,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
        ),
        actions: [
          PopupMenuButton<ReceivedFileSortBy>(
            tooltip: zh ? '排序' : 'Sort',
            icon: const Icon(LucideIcons.arrowDownWideNarrow, size: 18),
            onSelected: _onSortByChanged,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: ReceivedFileSortBy.createdAt,
                child: Text(zh ? '接收时间' : 'Received time'),
              ),
              PopupMenuItem(
                value: ReceivedFileSortBy.modified,
                child: Text(zh ? '修改时间' : 'Modified time'),
              ),
            ],
          ),
          if (_isSelectionMode)
            IconButton(
              tooltip: zh ? '退出选择' : 'Done selecting',
              onPressed: _exitSelectionMode,
              icon: const Icon(LucideIcons.x),
            ),
          IconButton(
            tooltip: zh ? '刷新' : 'Refresh',
            onPressed: _pullRefresh,
            icon: const Icon(LucideIcons.refreshCw, size: 19),
          ),
          if (wide && _isSaveFolderTab)
            Padding(
              padding: const EdgeInsets.only(right: 28, left: 12),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final path = await FileStore.getReceiveDir();
                  await openDirectoryInFileManager(path);
                },
                icon: const Icon(LucideIcons.folderOpen, size: 16),
                label: Text(zh ? '打开接收目录' : 'Open receive folder'),
              ),
            ),
          if (!wide)
            PopupMenuButton<String>(
              tooltip: zh ? '文件页面' : 'File pages',
              onSelected: (route) {
                if (ProductWorkspaceScope.maybeOf(context) != null) {
                  openProductRoute(context, route);
                } else if ([
                  '/files',
                  '/files/recent',
                  '/files/favorites',
                ].contains(route)) {
                  _selectView(route);
                } else {
                  openProductRoute(context, route);
                }
              },
              itemBuilder: (_) => [
                for (final (route, label) in [
                  ('/files', zh ? '本机文件' : 'Local files'),
                  ('/files/cloud', zh ? '云端文件' : 'Cloud files'),
                  ('/files/recent', zh ? '最近使用' : 'Recent files'),
                  ('/files/favorites', zh ? '收藏' : 'Favorites'),
                  ('/files/tasks', zh ? '传输任务' : 'Transfers'),
                  ('/files/connections', zh ? '连接设置' : 'Connections'),
                ])
                  PopupMenuItem(value: route, child: Text(label)),
              ],
            ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isSaveFolderTab)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.folder,
                      size: 15,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _saveFolderDisplayPath ??
                            (zh ? '正在读取接收目录…' : 'Loading receive folder…'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          openProductRoute(context, '/settings/receiving'),
                      child: Text(zh ? '更改' : 'Change'),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: zh ? '搜索文件名称' : 'Search file names',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: zh ? '清除搜索' : 'Clear search',
                        icon: const Icon(LucideIcons.x, size: 17),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  for (final (key, label) in [
                    ('all', zh ? '全部' : 'All'),
                    ('image', zh ? '图片' : 'Images'),
                    ('video', zh ? '视频' : 'Video'),
                    ('document', zh ? '文档' : 'Documents'),
                    ('audio', zh ? '音频' : 'Audio'),
                    ('archive', zh ? '压缩包' : 'Archives'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: _typeFilter == key,
                        showCheckmark: false,
                        label: Text(label),
                        onSelected: (_) {
                          setState(() {
                            _typeFilter = key;
                            _selectedFiles.clear();
                            _isSelectionMode = false;
                          });
                          if (_view == '/files/recent') unawaited(_loadFiles());
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (_isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _toggleSelectAll,
                      child: Text(zh ? '全选 / 取消全选' : 'Select / deselect all'),
                    ),
                    FilledButton.icon(
                      onPressed: _selectedFiles.isEmpty
                          ? null
                          : _addSelectedToPending,
                      icon: const Icon(LucideIcons.send, size: 16),
                      label: Text(zh ? '添加到待发送' : 'Add to send'),
                    ),
                    if (_isMobile)
                      IconButton(
                        onPressed: _shareSelectedFiles,
                        tooltip: l10n.fmTooltipShareSelection,
                        icon: const Icon(LucideIcons.share2, size: 18),
                      ),
                    IconButton(
                      onPressed: _selectedFiles.isEmpty
                          ? null
                          : _deleteSelectedFiles,
                      tooltip: l10n.chatTooltipDelete,
                      icon: Icon(
                        LucideIcons.trash2,
                        size: 18,
                        color: colors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            if (MediaQuery.sizeOf(context).width >= 1000)
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Checkbox(
                        value:
                            files.isNotEmpty &&
                            _selectedFiles.length == files.length,
                        onChanged: (_) {
                          setState(() => _isSelectionMode = true);
                          _toggleSelectAll();
                        },
                      ),
                    ),
                    Expanded(
                      child: Text(
                        zh ? '文件名称' : 'Name',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        zh ? '大小' : 'Size',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 125,
                      child: Text(
                        zh ? '修改时间' : 'Modified',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 88),
                  ],
                ),
              ),
            Expanded(
              child: busy
                  ? const Center(child: CircularProgressIndicator())
                  : _isSaveFolderTab && _saveFolderError != null
                  ? _buildSaveFolderTabBody(context)
                  : files.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _view == '/files/favorites'
                                ? LucideIcons.star
                                : LucideIcons.folderOpen,
                            size: 38,
                            color: colors.textTertiary,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _searchQuery.isNotEmpty
                                ? (zh ? '没有匹配的文件' : 'No matching files')
                                : _view == '/files/favorites'
                                ? (zh
                                      ? '收藏常用文件，随时找到它们'
                                      : 'Star files to find them here')
                                : (zh
                                      ? '接收的文件会显示在这里'
                                      : 'Received files appear here'),
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _pullRefresh,
                            child: Text(zh ? '刷新' : 'Refresh'),
                          ),
                        ],
                      ),
                    )
                  : _buildTimelineView(
                      context,
                      files: files,
                      hasMore: _view == '/files/recent' && _hasMore,
                    ),
            ),
          ],
        ),
      ),
    );
    Widget body = scaffold;
    if (_isDesktop && !widget.embedded) {
      body = DesktopPasteShortcuts(
        onPasteFiles: _handleDesktopPaste,
        child: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyC, control: true):
                _FmCopyFilesIntent(),
            SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                _FmCopyFilesIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _FmCopyFilesIntent: CallbackAction<_FmCopyFilesIntent>(
                onInvoke: (_) {
                  unawaited(_copyFilesToClipboard());
                  return null;
                },
              ),
            },
            child: body,
          ),
        ),
      );
    }
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) _exitSelectionMode();
      },
      child: body,
    );
  }

  Widget _buildSaveFolderTabBody(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    if (_saveFolderLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_saveFolderError != null) {
      return RefreshIndicator(
        onRefresh: _pullRefresh,
        color: theme.colorScheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.folderX,
                      size: 64,
                      color: colors.textTertiary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _saveFolderErrorMessage(l10n),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    if (_saveFolderDisplayPath != null &&
                        _saveFolderDisplayPath!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.fmSaveFolderPathLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      SelectableText(
                        _saveFolderDisplayLabel != null &&
                                _saveFolderDisplayLabel!.isNotEmpty
                            ? '${_saveFolderDisplayLabel!}\n${_saveFolderDisplayPath!}'
                            : _saveFolderDisplayPath!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _openSettings,
                      child: Text(l10n.fmSaveFolderGoSettings),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    final files = _activeFiles;
    if (files.isEmpty) {
      return RefreshIndicator(
        onRefresh: _pullRefresh,
        color: theme.colorScheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _saveFolderSearchQuery.isNotEmpty
                          ? LucideIcons.searchX
                          : LucideIcons.folderOpen,
                      size: 64,
                      color: colors.textTertiary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _saveFolderSearchQuery.isNotEmpty
                          ? l10n.fmEmptyNoMatch
                          : l10n.fmSaveFolderEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: _buildTimelineView(context, files: files, hasMore: false),
      ),
    );
  }

  Widget _buildTimelineView(
    BuildContext context, {
    required List<ReceivedFileInfo> files,
    bool? hasMore,
  }) {
    final colors = context.appColors;
    final showLoadMore = hasMore ?? _hasMore;
    final itemCount = files.length + (showLoadMore ? 1 : 0);
    return RefreshIndicator(
      onRefresh: _pullRefresh,
      color: Theme.of(context).colorScheme.primary,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        controller: _scrollController,
        padding: _listVerticalPadding(context),
        itemCount: itemCount,
        separatorBuilder: (_, index) {
          if (index >= files.length - 1) return const SizedBox.shrink();
          return Divider(height: 1, color: colors.border, indent: 68);
        },
        itemBuilder: (context, index) {
          if (index >= files.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _buildFileItem(context, files[index]);
        },
      ),
    );
  }

  Widget _buildFileItem(BuildContext context, ReceivedFileInfo file) {
    final colors = context.appColors;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final selected = _selectedFiles.contains(file.path);
    void select(bool? checked) {
      setState(() {
        _isSelectionMode = true;
        if (checked == true) {
          _selectedFiles.add(file.path);
        } else {
          _selectedFiles.remove(file.path);
          if (_selectedFiles.isEmpty) _isSelectionMode = false;
        }
      });
    }

    final row = Material(
      color: selected ? colors.accentSoft : colors.surface,
      child: InkWell(
        onTap: _isSelectionMode
            ? () => select(!selected)
            : () => _openFile(file),
        onLongPress: () => select(!selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (wide || _isSelectionMode)
                SizedBox(
                  width: 44,
                  child: Checkbox(value: selected, onChanged: select),
                ),
              FileIconWidget(
                category: file.category,
                size: 32,
                filePath: file.path,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    if (!wide) ...[
                      const SizedBox(height: 5),
                      Text(
                        '${formatFileSize(file.size)} · ${_formatTime(context, file.modified)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (wide) ...[
                SizedBox(
                  width: 90,
                  child: Text(
                    formatFileSize(file.size),
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ),
                SizedBox(
                  width: 125,
                  child: Text(
                    _formatTime(context, file.modified),
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ),
              ],
              IconButton(
                onPressed: () => _toggleFavorite(file),
                tooltip: _favorites.contains(file.path)
                    ? (zh ? '取消收藏' : 'Unstar')
                    : (zh ? '收藏' : 'Star'),
                icon: Icon(
                  LucideIcons.star,
                  size: 17,
                  color: _favorites.contains(file.path)
                      ? Theme.of(context).colorScheme.primary
                      : colors.textTertiary,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: zh ? '文件操作' : 'File actions',
                icon: const Icon(LucideIcons.ellipsis, size: 18),
                onSelected: (value) {
                  switch (value) {
                    case 'open':
                      _openFile(file);
                      break;
                    case 'send':
                      _addToPending(file);
                      break;
                    case 'info':
                      _showFileInfo(file);
                      break;
                    case 'folder':
                      _revealInFolder(file);
                      break;
                    case 'share':
                      _shareFile(file);
                      break;
                    case 'delete':
                      _deleteFile(file);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'open', child: Text(zh ? '打开' : 'Open')),
                  PopupMenuItem(
                    value: 'send',
                    child: Text(zh ? '添加到待发送' : 'Add to send'),
                  ),
                  PopupMenuItem(
                    value: 'info',
                    child: Text(zh ? '文件信息' : 'File details'),
                  ),
                  if (_isDesktop)
                    PopupMenuItem(
                      value: 'folder',
                      child: Text(zh ? '在文件夹中显示' : 'Show in folder'),
                    ),
                  if (_isMobile)
                    PopupMenuItem(
                      value: 'share',
                      child: Text(zh ? '分享' : 'Share'),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      zh ? '删除' : 'Delete',
                      style: TextStyle(color: colors.danger),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!_isDesktop) return row;
    return DesktopFileDragSource(
      paths: resolveFileManagerDragPaths(
        currentPath: file.path,
        isSelectionMode: _isSelectionMode,
        selectedFiles: _selectedFiles,
      ),
      enabled: !_isSelectionMode || selected,
      child: GestureDetector(
        onSecondaryTapUp: (details) =>
            _showFileContextMenu(file, details.globalPosition),
        child: row,
      ),
    );
  }

  void _showFileContextMenu(ReceivedFileInfo file, Offset globalPosition) {
    final l10n = AppLocalizations.of(context);
    final colors = context.appColors;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );
    showMenu<void>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<void>(
          onTap: () => _showFileInfo(file),
          child: Text(l10n.fmFileInfoAction),
        ),
        PopupMenuItem<void>(
          onTap: () => unawaited(_copyFilesToClipboard([file.path])),
          child: Text(l10n.fileClipboardCopy),
        ),
        PopupMenuItem<void>(
          onTap: () => _openFile(file),
          child: Text(l10n.chatMenuOpen),
        ),
        PopupMenuItem<void>(
          onTap: () => unawaited(_revealInFolder(file)),
          child: Text(l10n.fmRevealInFolder),
        ),
        if (FileExportService.isSupported &&
            !SaveFolderListingService.isSaveFolderEntry(file))
          PopupMenuItem<void>(
            onTap: () => unawaited(_exportFile(file)),
            child: Text(_exportActionLabel(l10n)),
          ),
        PopupMenuItem<void>(
          onTap: () => _addToPending(file),
          child: Text(l10n.chatMenuAddToPending),
        ),
        PopupMenuItem<void>(
          onTap: () => unawaited(_deleteFile(file)),
          child: Row(
            children: [
              Icon(LucideIcons.trash2, size: 20, color: colors.danger),
              const SizedBox(width: 12),
              Text(
                l10n.fmDeleteConfirm,
                style: TextStyle(color: colors.danger),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(BuildContext context, DateTime dt) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return l10n.fmTimeJustNow;
    if (diff.inHours < 1) {
      return l10n.fmTimeMinutesAgo(diff.inMinutes);
    }
    if (diff.inDays < 1) {
      return l10n.fmTimeHoursAgo(diff.inHours);
    }
    if (diff.inDays < 7) {
      return l10n.fmTimeDaysAgo(diff.inDays);
    }
    return l10n.fmTimeMonthDayClock(
      dt.month,
      dt.day,
      dt.hour.toString().padLeft(2, '0'),
      dt.minute.toString().padLeft(2, '0'),
    );
  }
}

class _FmCopyFilesIntent extends Intent {
  const _FmCopyFilesIntent();
}
