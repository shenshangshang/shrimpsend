import '../models/pending_file_entry.dart';

/// Result of dispatching files from the visible pending outbox.
typedef PendingDispatchResult = ({
  List<PendingFileEntry> queued,
  int skipped,
});
