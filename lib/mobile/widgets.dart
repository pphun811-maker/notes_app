import 'package:flutter/material.dart';

import '../design.dart';

/// The hairline between two note rows: transparent -> grey -> grey -> transparent.
///
/// This detail was asked for explicitly. The mock-up generator
/// (`make_mockup_v5.py`, `faded_lines`) ramps the alpha linearly across the first
/// and last 22% of the line, and then holds full opacity in between.
///
/// Flutter's `LinearGradient` interpolates its stops linearly too, so a plain
/// gradient reproduces the ramp exactly - provided the four stops below are left
/// alone. Do not "prettify" them into a two-stop gradient with a smooth curve;
/// that would visibly shorten and darken the fade at both ends.
class FadingDivider extends StatelessWidget {
  const FadingDivider({super.key, this.left = 0, this.right = 0});

  final double left;
  final double right;

  @override
  Widget build(BuildContext context) {
    final Color color = NotesPalette.of(context).divider;
    const double fade = NotesMetrics.dividerFade;
    return SizedBox(
      height: NotesMetrics.dividerHeight,
      child: Padding(
        padding: EdgeInsets.only(left: left, right: right),
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  color.withAlpha(0),
                  color,
                  color,
                  color.withAlpha(0),
                ],
                stops: const <double>[0, fade, 1 - fade, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The white (or dark) card that groups every note row.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: NotesMetrics.cardMargin),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(NotesMetrics.cardRadius),
        boxShadow: palette.isDark
            // The mock-up drops the card shadow entirely in the dark theme.
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withAlpha(NotesMetrics.shadowAlpha),
                  offset: const Offset(0, NotesMetrics.shadowOffsetY),
                  blurRadius: NotesMetrics.shadowBlur,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NotesMetrics.cardRadius),
        child: child,
      ),
    );
  }
}

/// One row of the note card.
///
/// The mock-up draws every row by hand at fixed offsets, so this uses fixed
/// offsets too rather than a padded column: it is the only way to land exactly on
/// the designed baselines.
class NoteRow extends StatelessWidget {
  const NoteRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.selected,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;

  /// Null outside multi-select mode, otherwise whether this row is ticked.
  final bool? selected;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    final bool selecting = selected != null;
    // Multi-select shifts the text right to make room for the tick ring.
    final double textLeft = selecting
        ? NotesMetrics.rowTextLeftSelectedInCard
        : NotesMetrics.rowTextLeftInCard;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        height: NotesMetrics.rowHeight,
        child: Stack(
          children: <Widget>[
            if (selecting)
              Positioned(
                left: NotesMetrics.selectionRingCenterXInCard -
                    NotesMetrics.selectionRingDiameter / 2,
                top: NotesMetrics.rowHeight / 2 -
                    NotesMetrics.selectionRingDiameter / 2,
                child: _SelectionRing(selected: selected!),
              ),
            Positioned(
              left: textLeft,
              right: 16,
              top: NotesMetrics.rowTitleTop,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: NotesMetrics.rowTitleSize,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ),
            Positioned(
              left: textLeft,
              right: 16,
              top: NotesMetrics.rowSubtitleTop,
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: NotesMetrics.rowSubtitleSize,
                  color: palette.sub,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tick circle on a row in multi-select mode.
class _SelectionRing extends StatelessWidget {
  const _SelectionRing({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return Container(
      width: NotesMetrics.selectionRingDiameter,
      height: NotesMetrics.selectionRingDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? palette.amber : null,
        border: selected
            ? null
            : Border.all(
                color: palette.ring,
                width: NotesMetrics.selectionRingStroke,
              ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : null,
    );
  }
}

/// The round amber "new note" button in the bottom-right corner.
///
/// The user rejected a rounded square and asked for a white plus, so neither the
/// shape nor the icon colour is a theme default.
class NewNoteButton extends StatelessWidget {
  const NewNoteButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return SizedBox(
      width: NotesMetrics.fabDiameter,
      height: NotesMetrics.fabDiameter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.amber,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: palette.amber.withAlpha(62),
              offset: const Offset(0, 6),
              blurRadius: 12,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: const Center(
              child: _PlusGlyph(
                arm: NotesMetrics.fabPlusArm,
                stroke: NotesMetrics.fabPlusStroke,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plus drawn to the designed arm length and stroke width.
class _PlusGlyph extends StatelessWidget {
  const _PlusGlyph({required this.arm, required this.stroke});

  final double arm;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: arm * 2 + stroke,
      height: arm * 2 + stroke,
      child: CustomPaint(painter: _PlusPainter(stroke: stroke)),
    );
  }
}

class _PlusPainter extends CustomPainter {
  const _PlusPainter({required this.stroke});

  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final Offset centre = size.center(Offset.zero);
    canvas.drawLine(
      Offset(0, centre.dy),
      Offset(size.width, centre.dy),
      paint,
    );
    canvas.drawLine(
      Offset(centre.dx, 0),
      Offset(centre.dx, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlusPainter oldDelegate) => oldDelegate.stroke != stroke;
}
