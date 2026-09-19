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
  static const String closeSearch = '关闭搜索';
  static const String exitSelection = '退出多选';

  static const String emptyTitle = '还没有笔记';

  /// The empty state used to say "点右下角的『新建』". That stopped being true when the
  /// floating button was removed and "new note" moved to the top bar.
  static const String emptyDetail = '点顶栏的“＋”写第一篇。';

  /// The empty state's last line: the folder the app is actually looking at.
  static String emptyFolderNote(String path) =>
      '笔记就是这个文件夹里的 .md 文本文件：\n$path';

  static const String searchEmptyTitle = '没有匹配的笔记';
  static const String searchEmptyDetail = '换个词试试。';

  static const String errorTitle = '打不开笔记文件夹';

  /// "无法打开笔记文件夹：Permission denied"
  static String errorOpeningFolder(String reason) => '无法打开笔记文件夹：$reason';

  /// The error state's second line, under [errorOpeningFolder]: which folder it was.
  static String errorFolder(String message, String path) =>
      '$message\n\n文件夹：$path';

  /// "新建失败：No space left on device"
  static String createFailed(String reason) => '新建失败：$reason';

  // --- Syncthing conflict copies -------------------------------------------
  /// The heading of the conflict page, and the ⋮ menu entry.
  static const String conflicts = '冲突副本';

  /// "发现 1 份冲突副本"
  static String conflictsFound(int count) => '发现 $count 份冲突副本';

  /// The ⋮ menu entry: "冲突副本（2）".
  ///
  /// The count is in the label because the entry only appears when there is at least one, so
  /// it doubles as the answer to "how many".
  static String conflictsMenu(int count) => '$conflicts（$count）';

  /// The one-line explanation shown on the conflict page and above a copy's contents.
  static const String conflictsExplain =
      '两端同时改了同一篇笔记时，Syncthing 会把其中一份另存为“冲突副本”。'
      '它不会被当成笔记列出来，也不会被自动删除。';

  /// Shown instead of a copy's contents when the file could not be read.
  static const String conflictUnreadable = '这份副本没有读出来';

  /// The conflict page with nothing on it, which is what the user sees if they follow the
  /// page from a banner that has since become stale.
  static const String conflictNone = '现在没有冲突副本';

  static const String conflictBack = '返回';

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

  /// The placeholder in the desktop editor's title field, which is the file name.
  static const String editorTitleHint = '标题';

  // --- desktop -------------------------------------------------------------
  /// The right-hand pane with no note in it.
  static const String nothingOpenTitle = '没有打开的笔记';
  static const String nothingOpenDetail = '从左边选一篇，或按 Ctrl+N 新建一篇。';

  static const String desktopNewNote = '新建';

  /// The button at the end of the tab strip. It sits with the tabs rather than with the note
  /// list because writing a new note is what the tabs are for.
  static const String desktopNewTab = '新建一篇笔记';
  static const String desktopSearchHint = '搜索笔记';
  static const String desktopNoteCountSection = '全部笔记';
  static const String desktopPinnedSection = '已置顶';

  /// A note with nothing written in it yet. The design puts this where the one-line preview
  /// would otherwise be, so an empty row still reads as a row rather than as a gap.
  static const String desktopEmptyNote = '（空）';

  /// "共 8 篇"
  static String desktopNoteTotal(int count) => '共 $count 篇';
  static const String desktopCloseNote = '关闭笔记';

  static const String windowMinimize = '最小化';
  static const String windowMaximize = '最大化';
  static const String windowRestore = '还原';
  static const String windowClose = '关闭';

  /// The button in the band that folds the note list away, and puts it back. The shortcut is
  /// spelled out because there is nowhere else for the user to find out about it.
  static const String desktopSidebarCollapse = '收起列表 (Ctrl+B)';
  static const String desktopSidebarExpand = '展开列表 (Ctrl+B)';

  /// The theme button says what pressing it *does*, not what the current state is - the icon
  /// shows the state.
  static const String desktopThemeToLight = '切换到浅色';
  static const String desktopThemeToDark = '切换到深色';
  static const String desktopThemeToSystem = '跟随系统';

  // --- the desktop note list's right-click menu ------------------------------
  //
  // "删除" is not one of these: it is [delete], which the phone's own menus already use. The
  // confirmation's heading is [confirmDeleteOne] for the same reason - it is the same sentence.
  static const String desktopMenuOpen = '打开';
  static const String desktopMenuRename = '重命名';
  static const String desktopMenuReveal = '在资源管理器中显示';
  static const String desktopMenuCopyPath = '复制路径';
  static const String desktopMenuPin = '置顶';
  static const String desktopMenuUnpin = '取消置顶';

  /// The line under [confirmDeleteOne] on the desktop.
  ///
  /// It says "回收站" where the phone's [deleteWarning] says "永久删除", because on Windows the
  /// note really does go somewhere it can be got back from - and telling the user it cannot be
  /// undone when it can would be its own kind of wrong.
  static String desktopDeleteDetail(String title) =>
      '「$title」会移到回收站，需要的话可以从那里找回来。';

  static String desktopDeletedOne(String title) => '已删除「$title」';
  static String desktopDeleteFailed(String reason) => '删除失败：$reason';
  static const String desktopPathCopied = '路径已复制';
  static const String desktopRevealFailed = '打不开资源管理器';
  static String desktopPinnedNote(String title) => '已置顶「$title」';
  static String desktopUnpinnedNote(String title) => '已取消置顶「$title」';

  // --- a note that somebody else changed ------------------------------------
  /// Shown in the editor when the file on disk has been changed by something else - Syncthing
  /// bringing the phone's copy over, or another editor - while this window has unsaved text.
  static const String externalChangeTitle = '这篇笔记在磁盘上被改了';
  static const String externalChangeDetail = '为免盖掉对方的改动，现在不会自动保存。';

  /// The two answers. Taking the file's version throws this window's text away; keeping it
  /// writes over what the other machine wrote.
  static const String externalChangeTakeDisk = '用磁盘上的';
  static const String externalChangeKeepMine = '保留我的';

  /// The same event with nothing unsaved here, so the file's version was simply taken. Nobody
  /// had to be asked, but the text on screen changing by itself still needs saying.
  static const String externalChangeReloaded = '这篇笔记在磁盘上被改过，已重新载入';

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

  /// "改名失败：Permission denied"
  static String renameFailed(String reason) => '改名失败：$reason';

  // --- editor top bar ------------------------------------------------------
  static const String back = '返回';
  static const String undo = '撤销';
  static const String redo = '重做';
  static const String moreActions = '更多';

  /// The tick beside the back arrow. Puts the keyboard and the caret away so the note can
  /// be read without anything blinking at you.
  static const String finishEditing = '完成';

  /// The right-hand end of the status line.
  ///
  /// "已保存 · 128 字"; while a write is in flight it says so instead, and a note that
  /// could not be written says that rather than pretending to be saved.
  static String savedStatus(int characters) => '已保存 · $characters 字';
  static const String savingStatus = '正在保存…';
  static const String unsavedStatus = '未保存';
  static const String saveFailedStatus = '保存失败';

  /// The small chevron that folds the title away, and the one that brings it back.
  static const String titleCollapse = '收起标题';
  static const String titleExpand = '展开标题';

  // --- editor toolbar ------------------------------------------------------
  static const String toolbarCollapse = '收起工具条';
  static const String toolbarExpand = '展开工具条';
  static const String toolTextStyle = '格式';
  static const String toolBold = '加粗';
  static const String toolItalic = '斜体';
  static const String toolHeading = '标题';
  static const String toolCheckbox = '待办';

  // --- format panel --------------------------------------------------------
  static const String formatTitle = '格式';
  static const String formatClose = '关闭';
  static const String pickLineHeight = '行距';
  static const String fontFamilySystem = '系统字体';
  static const String fontFamilyMono = '等宽字体';
  static const String toolStrike = '删除线';
  static const String toolCode = '行内代码';
  static const String toolDivider = '分割线';
  static const String toolBulletList = '无序列表';
  static const String toolNumberList = '编号列表';
  static const String toolIndent = '缩进';
  static const String toolOutdent = '取消缩进';
  static const String toolQuote = '引用';
  static const String toolDate = '插入日期';

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
