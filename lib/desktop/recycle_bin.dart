import 'dart:async';
import 'dart:io';

/// Sends [file] to the Windows Recycle Bin.
///
/// Returns `null` when the file is gone, or a short reason the caller can show the user.
///
/// **It never falls back to deleting the file for good.** A note is the only copy of something
/// the user wrote, and the whole point of asking for the recycle bin is that a mistake can be
/// undone. A delete that silently became permanent because PowerShell was unavailable would be
/// worse than a delete that did not happen.
///
/// The work is done by PowerShell rather than by `File.delete`, because `dart:io` has no way to
/// ask for the recycle bin: it can only unlink. `Microsoft.VisualBasic.FileIO.FileSystem` is the
/// documented wrapper around `SHFileOperation` with `FOF_ALLOWUNDO`, it ships with Windows, and
/// it needs no package - the same reasoning that lets the accent be read with `reg`.
///
/// The path travels in an environment variable rather than inside the command text. A note's
/// title is a file name and can hold a quote, a backtick, a `$` or a semicolon; there is no
/// escaping of those into a PowerShell one-liner that is worth getting right, and this way none
/// of them ever reaches the parser.
Future<String?> deleteToRecycleBin(File file) async {
  if (!Platform.isWindows) {
    // Nothing else in this project ships a desktop build, and the tests run on the host. A plain
    // delete keeps the flow exercisable rather than pretending there is a bin to use.
    try {
      await file.delete();
      return null;
    } on FileSystemException catch (error) {
      return error.osError?.message ?? error.message;
    }
  }

  final Process process;
  try {
    process = await Process.start(
      'powershell.exe',
      const <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        _script,
      ],
      environment: <String, String>{_targetVariable: file.path},
    );
  } on ProcessException catch (error) {
    return error.message;
  }

  // Draining both pipes matters even though the output is thrown away: a PowerShell that filled
  // a pipe buffer would block on its own diagnostics and never exit.
  final Future<String> errors = process.stderr.transform(systemEncoding.decoder).join();
  final Future<String> output = process.stdout.transform(systemEncoding.decoder).join();

  final int code;
  try {
    code = await process.exitCode.timeout(const Duration(seconds: 20));
  } on TimeoutException {
    process.kill();
    return '操作超时';
  }
  final String stderr = (await errors).trim();
  await output;

  // PowerShell exiting 0 only means the command did not throw. Whether the file actually left is
  // the thing being asked about, so it is checked rather than assumed.
  if (await file.exists()) return _firstLine(stderr) ?? '文件仍在磁盘上';
  if (code != 0) return _firstLine(stderr) ?? 'PowerShell 退出码 $code';
  return null;
}

/// The environment variable the target path travels in.
const String _targetVariable = 'NOTES_RECYCLE_TARGET';

/// The whole of the PowerShell side, on one line so no continuation rule has to be relied on.
///
/// `Add-Type` comes first because `Microsoft.VisualBasic` is not loaded into a bare PowerShell
/// session. `OnlyErrorDialogs` is the silent-but-for-errors setting; the method can still raise
/// a modal dialog, so the caller's timeout is what keeps a stuck dialog from hanging the app.
const String _script =
    r"$ErrorActionPreference = 'Stop'; "
    r'Add-Type -AssemblyName Microsoft.VisualBasic; '
    r'[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('
    r'$env:NOTES_RECYCLE_TARGET, '
    r'[Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, '
    r'[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)';

String? _firstLine(String text) {
  for (final String line in text.split('\n')) {
    final String trimmed = line.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}
