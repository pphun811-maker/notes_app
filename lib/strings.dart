/// Every user-visible string in one place.
///
/// The app is deliberately not localised - there is no `intl` dependency and no
/// `MaterialApp.localizationsDelegates` - so this file is simply a tidy index of
/// the Chinese text the UI shows. Keeping it here means a wording change never
/// requires hunting through widget code.
abstract final class NotesStrings {
  static const String appTitle = 'Notes';

  // --- list page -----------------------------------------------------------
  static const String listTitle = '笔记';

  /// "6 篇笔记".
  static String noteCount(int count) => '$count 篇笔记';

  static const String searchHint = '搜索笔记';
  static const String newNote = '新建笔记';
  static const String rescan = '重新扫描笔记文件夹';
  static const String selectMode = '选择笔记';

  static const String emptyTitle = '还没有笔记';
  static const String emptyDetail = '点右下角的“新建”写第一篇。';

  static const String errorTitle = '打不开笔记文件夹';

  // --- multi-select --------------------------------------------------------
  /// "已选 2 篇".
  static String selectedCount(int count) => '已选 $count 篇';
  static const String selectAll = '全选';
  static const String deselectAll = '取消全选';
  static const String deleteSelected = '删除';

  /// "删除这 3 篇笔记？"
  static String confirmDeleteMany(int count) => '删除这 $count 篇笔记？';
  static const String confirmDeleteOne = '删除这篇笔记？';

  /// "“购物清单”将被永久删除，无法撤销。"
  static String deleteWarning(String titles) => '“$titles”将被永久删除，无法撤销。';

  static const String cancel = '取消';
  static const String delete = '删除';

  /// "已删除 2 篇笔记"
  static String deletedMany(int count) => '已删除 $count 篇笔记';
  static const String deletedOne = '已删除 1 篇笔记';

  static const String deleteFailed = '删除失败';

  // --- editor --------------------------------------------------------------
  static const String editorHint = '在这里写点什么……';

  /// Shown instead of the editor when the note could not be read. The note stays
  /// read-only until the user retries, so that an empty editor can never replace
  /// contents the app never managed to read.
  static const String loadFailedTitle = '这篇笔记没有读出来';
  static const String loadFailedDetail = '为避免把原有内容覆盖掉，现在不能编辑。';
  static const String retryLoad = '重新读取';

  /// "读取失败：Permission denied"
  static String readFailed(String reason) => '读取失败：$reason';

  /// "保存失败：No space left on device（会自动重试）"
  static String saveFailed(String reason) => '保存失败：$reason（会自动重试）';

  // --- editor top bar ------------------------------------------------------
  static const String back = '返回';
  static const String undo = '撤销';
  static const String redo = '重做';
  static const String moreActions = '更多';

  /// The right-hand end of the status line.
  ///
  /// "已保存 · 128 字"; while a write is in flight it says so instead, and a note that
  /// could not be written says that rather than pretending to be saved.
  static String savedStatus(int characters) => '已保存 · $characters 字';
  static const String savingStatus = '正在保存…';
  static const String unsavedStatus = '未保存';
  static const String saveFailedStatus = '保存失败';

  // --- editor toolbar ------------------------------------------------------
  static const String toolbarCollapse = '收起工具条';
  static const String toolbarExpand = '展开工具条';
  static const String toolTextStyle = '格式';
  static const String toolBold = '加粗';
  static const String toolItalic = '斜体';
  static const String toolHeading = '标题';
  static const String toolCheckbox = '待办';

  /// The format panel is the next piece of work; this is what the two buttons that
  /// open it say until then.
  static const String formatPanelPending = '格式面板还在制作中';

  // --- editor menu ---------------------------------------------------------
  static const String copyAsPlainText = '复制为纯文本';
  static const String copyAsMarkdown = '复制为 Markdown';
  static const String copiedPlain = '已复制（去掉 Markdown 符号）';
  static const String copiedMarkdown = '已复制（Markdown 原文）';

  // --- permission page -----------------------------------------------------
  static const String permissionTitle = '需要“所有文件访问权限”';
  static const String permissionDetail =
      '笔记以普通文本文件的形式放在手机的共享文件夹里，'
      '这样 Syncthing 才能把它同步到电脑。\n\n'
      '请在弹出的设置页面里打开“允许管理所有文件”，然后返回本应用。';
  static const String grantAccess = '去授权';
  static const String recheckAccess = '我已授权，重新检查';
}
