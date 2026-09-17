/// Design tokens for the Notes app.
///
/// Every value here is copied from the mock-up generators in `E:\beta\design\scripts\`
/// (`make_mockup_v5.py`, `make_mockup_v4.py`, `make_mockup_editor3.py`), which are the
/// authoritative source for the numbers in `HANDOFF_PHASE3.md` section 5. Do not
/// "tidy" these numbers: they were measured pixel by pixel, not estimated.
///
/// Nothing in this file has any behaviour. It is safe to change values here without
/// touching the data layer.
library;

import 'package:flutter/material.dart';

/// Light palette.
///
/// `kAmber` was sampled pixel by pixel from the `+` button of ColorOS Notes on the
/// user's own phone (see `design/scripts/sample_color.py`); all 27,924 pixels of that
/// button hold this single value, with no gradient.
abstract final class NotesColors {
  // --- light ---------------------------------------------------------------
  static const Color page = Color(0xFFF4F5F7);
  static const Color card = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF17171A);
  static const Color sub = Color(0xFF898A8E);
  static const Color ter = Color(0xFFAAABAF);
  static const Color divider = Color(0xFFDFE0E5);

  /// The accent. **Never use this as a text colour** - on white it only reaches a
  /// contrast ratio of 1.8:1. Use [amberText] whenever the accent has to be read.
  static const Color amber = Color(0xFFFFB200);

  /// The accent darkened until it is legible as text on a white card.
  static const Color amberText = Color(0xFFB07400);

  /// Pale amber wash used to fill a selected chip.
  static const Color amberChip = Color(0xFFFDF0CC);

  static const Color red = Color(0xFFE2484D);
  static const Color disabled = Color(0xFFCBCCD1);
  static const Color toolbarBg = Color(0xFFFAFAFB);
  static const Color btn = Color(0xFFF5F5F6);

  // --- dark ----------------------------------------------------------------
  static const Color darkPage = Color(0xFF121214);
  static const Color darkCard = Color(0xFF1C1C1F);
  static const Color darkInk = Color(0xFFF0F0F3);
  static const Color darkSub = Color(0xFF96979C);
  static const Color darkDivider = Color(0xFF3E3E44);

  /// The accent barely changes in the dark theme: the yellow stays, lifted slightly.
  static const Color darkAmber = Color(0xFFFFB814);

  /// The unselected selection ring in the dark theme.
  static const Color darkRing = Color(0xFF4E4E54);
}

/// Layout numbers, in logical pixels.
abstract final class NotesMetrics {
  /// The mock-ups are drawn on a 412 x 900 canvas, which matches the user's phone
  /// (a 1240px screenshot at DPR 3 is about 413dp wide).
  static const double designWidth = 412;
  static const double designHeight = 900;

  /// Top bar icon centres, as an inset from the right edge: x = width - [iconInset].
  ///
  /// The three icons are evenly spaced 50dp apart, right to left: more, search,
  /// new note. The "+" replaced the old floating button, which the user removed
  /// because a bottom-pinned disc looked stranded once the card got short.
  static const double moreIconInset = 34;
  static const double searchIconInset = 84;
  static const double newNoteIconInset = 134;

  /// The bar's height and the icon centres inside it.
  ///
  /// **This bar is deliberately much tighter than the 412 x 900 mock-up.** The
  /// mock-up put the title's top at y = 82 and the card at y = 168 on a canvas
  /// that had no status bar; on the real phone that left a large dead band under
  /// the status bar, which the user rejected. The title now sits 27dp below the
  /// top of the content area and the card follows the note count closely, so the
  /// header reads as one block stuck to the status bar.
  static const double barHeight = 72;
  static const double barIconCenterY = 27;

  /// Header text, as insets from the left edge.
  static const double headerLeft = 24;
  static const double titleTop = 18;
  static const double titleSize = 31;
  static const double countTop = 54;
  static const double countSize = 14;

  /// The grouped card.
  ///
  /// [cardTop] is the card's top edge measured **from the top of the page**.
  ///
  /// It used to be applied as "this far below the bottom of the header", which is
  /// what opened the dead band under the top bar that the user rejected: the bar
  /// plus its inset already comes to about 112dp, so the card landed near 344dp.
  /// The card now hangs directly off the header, separated only by [cardGap].
  static const double cardTop = 168;

  /// The sliver of page background between the header block and the card.
  ///
  /// This is what makes the card look "stuck to" the top bar rather than floating
  /// in the middle of the screen. Keep it small.
  static const double cardGap = 14;

  static const double cardMargin = 16;
  static const double cardRadius = 18;
  static const double cardPaddingTop = 4;
  static const double cardPaddingBottom = 12;
  static const double shadowOffsetY = 5;
  static const double shadowBlur = 12;
  static const int shadowAlpha = 26;

  /// One note row.
  ///
  /// The row is 74 and the hairline is 1, giving the 75dp pitch the tightened
  /// layout uses. (The original 412 x 900 mock-up used an 84dp pitch; the user
  /// asked for shorter, denser rows.)
  static const double rowHeight = 74;

  /// The horizontal text inset **from the screen edge**.
  ///
  /// The original design quoted these as absolute positions on its 412dp canvas
  /// (`c.text(TEXT_X, ...)` with `TEXT_X = 34`), and they are confirmed by the
  /// multi-select mock-up, which puts the tick ring's centre at x = 48 and the
  /// text at x = 74. Subtracting the card's margin gives the inset *inside* the
  /// card, which is what the widgets actually need.
  ///
  /// The user asked for the hairlines to run wider than the text, so the row text
  /// was pulled in to 30 while the divider keeps its own, longer span.
  static const double rowTextLeft = 30;
  static const double rowTextLeftSelected = 74;
  static const double selectionRingCenterX = 48;

  /// The above, converted to coordinates inside the card.
  static const double rowTextLeftInCard = rowTextLeft - cardMargin;
  static const double rowTextLeftSelectedInCard =
      rowTextLeftSelected - cardMargin;
  static const double selectionRingCenterXInCard =
      selectionRingCenterX - cardMargin;

  /// Where the hairline starts and ends, again as insets from the screen edge.
  ///
  /// Wider than the text on purpose: 24dp in from each side, so the fade has
  /// somewhere to run.
  static const double dividerInset = 24;
  static const double dividerInsetInCard = dividerInset - cardMargin;

  static const double rowTitleTop = 16;
  static const double rowTitleSize = 17;
  static const double rowSubtitleTop = 38;
  static const double rowSubtitleSize = 13.5;
  static const double dividerHeight = 1;

  /// How much of each end of a divider fades out: transparent -> grey -> grey -> transparent.
  static const double dividerFade = 0.22;

  /// How far the list is pulled down while refreshing.
  static const double pullToRefreshPull = 66;
  static const double refreshSpinnerRadius = 11;
  static const double refreshSpinnerStroke = 2.6;
  static const double refreshSpinnerTop = 30;

  /// Multi-select mode.
  static const double selectionBarBottom = 92;
  static const double selectionRingDiameter = 23;
  static const double selectionRingStroke = 1.8;
  static const double selectionCloseCenterX = 31;
  static const double selectionTitleLeft = 58;
  static const double selectionTitleSize = 19;
  static const double selectAllRight = 78;
  static const double selectAllSize = 15;
}

/// The single source of truth for the app's `ThemeData`, light and dark.
abstract final class NotesTheme {
  /// The accent as a Material [ColorScheme], so stock widgets that we do not draw
  /// ourselves (dialogs, snack bars, the text selection handles) stay on-palette.
  static ColorScheme _scheme(Color accent, Brightness brightness) {
    return ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      surface: brightness == Brightness.light
          ? NotesColors.page
          : NotesColors.darkPage,
    );
  }

  static ThemeData light() {
    final ColorScheme scheme = _scheme(NotesColors.amber, Brightness.light);
    return _base(scheme, NotesColors.ink).copyWith(
      scaffoldBackgroundColor: NotesColors.page,
    );
  }

  static ThemeData dark() {
    final ColorScheme scheme = _scheme(NotesColors.darkAmber, Brightness.dark);
    return _base(scheme, NotesColors.darkInk).copyWith(
      scaffoldBackgroundColor: NotesColors.darkPage,
    );
  }

  /// Everything both themes share. The app draws its own chrome, so this is
  /// deliberately thin: only the pieces that come from stock Material widgets.
  static ThemeData _base(ColorScheme scheme, Color ink) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // The user asked for the system font, so no `fontFamily` is set anywhere.
      // On Android that resolves to Noto Sans CJK, which is exactly what the mock-ups use.
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: ink),
        bodySmall: TextStyle(color: NotesColors.sub),
      ),
    );
  }
}

/// The colour set the list and editor draw with, resolved for the current brightness.
///
/// Grab it with `NotesPalette.of(context)`.
class NotesPalette {
  const NotesPalette({
    required this.page,
    required this.card,
    required this.ink,
    required this.sub,
    required this.divider,
    required this.amber,
    required this.accentText,
    required this.ring,
    required this.isDark,
  });

  final Color page;
  final Color card;
  final Color ink;
  final Color sub;
  final Color divider;
  final Color amber;

  /// The accent when it has to be legible as text.
  final Color accentText;

  /// The unselected selection ring.
  final Color ring;

  final bool isDark;

  static const NotesPalette light = NotesPalette(
    page: NotesColors.page,
    card: NotesColors.card,
    ink: NotesColors.ink,
    sub: NotesColors.sub,
    divider: NotesColors.divider,
    amber: NotesColors.amber,
    accentText: NotesColors.amberText,
    ring: NotesColors.disabled,
    isDark: false,
  );

  /// In the dark theme the accent-as-text stays simply the secondary grey; the
  /// mock-up generator does exactly this (`atext = D_SUB if dark`).
  static const NotesPalette dark = NotesPalette(
    page: NotesColors.darkPage,
    card: NotesColors.darkCard,
    ink: NotesColors.darkInk,
    sub: NotesColors.darkSub,
    divider: NotesColors.darkDivider,
    amber: NotesColors.darkAmber,
    accentText: NotesColors.darkSub,
    ring: NotesColors.darkRing,
    isDark: true,
  );

  static NotesPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
