sealed class StorageError implements Exception {
  const StorageError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The file is not a PostIt workspace database.
class NotAWorkspaceError extends StorageError {
  const NotAWorkspaceError(String path)
    : super('$path is not a PostIt workspace file');
}

/// The file was written by a newer PostIt (FR-WS-001).
class UnsupportedSchemaError extends StorageError {
  UnsupportedSchemaError(this.found, this.supported)
    : super(
        'Workspace schema v$found is newer than this app supports (v$supported). '
        'Update PostIt to open it.',
      );

  final int found;
  final int supported;
}

/// Another process holds the workspace open (FR-WS-004).
class WorkspaceLockedError extends StorageError {
  const WorkspaceLockedError(String path)
    : super('$path is in use by another PostIt window or process');
}

/// The operating system refused access to the file or its folder.
class WorkspaceAccessError extends StorageError {
  const WorkspaceAccessError(String path)
    : super(
        'PostIt cannot read or write $path. Check the folder permissions '
        '(on macOS, allow access to the Documents folder in System Settings, '
        'Privacy & Security).',
      );
}

class NotFoundError extends StorageError {
  const NotFoundError(String what) : super('$what not found');
}

class InvalidOperationError extends StorageError {
  const InvalidOperationError(super.message);
}

class DuplicateNameError extends StorageError {
  const DuplicateNameError(String name) : super('"$name" already exists');
}
