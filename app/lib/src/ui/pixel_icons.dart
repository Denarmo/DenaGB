// SPDX-License-Identifier: GPL-3.0-or-later
// Hand-placed 1-bit pixel icons on a 9x9 grid, with an optional mid shade
// for depth (Pocket LCD look; docs/specs/pocket-lcd-ui.md).
import 'package:material_ui/material_ui.dart';

import 'pocket.dart';

/// One glyph: nine rows of nine cells. `#` is ink, `+` the mid shade, any
/// other character is empty.
class PixelGlyph {
  const PixelGlyph(this.rows);

  final List<String> rows;
}

/// The Pocket LCD icon set.
abstract final class PixelGlyphs {
  static const cart = PixelGlyph([
    '.#######.',
    '.#.....#.',
    '.#.###.#.',
    '.#.#+#.#.',
    '.#.###.#.',
    '.#.....#.',
    '.#.#.#.#.',
    '.#######.',
    '..#.#.#..',
  ]);
  static const gear = PixelGlyph([
    '....#....',
    '.#.###.#.',
    '..#####..',
    '.##...##.',
    '###.+.###',
    '.##...##.',
    '..#####..',
    '.#.###.#.',
    '....#....',
  ]);
  static const play = PixelGlyph([
    '..#......',
    '..##.....',
    '..###....',
    '..####...',
    '..#####..',
    '..####...',
    '..###....',
    '..##.....',
    '..#......',
  ]);
  static const floppy = PixelGlyph([
    '########.',
    '#.#..#.##',
    '#.####..#',
    '#.......#',
    '#.#####.#',
    '#.#+++#.#',
    '#.#+++#.#',
    '#.#####.#',
    '#########',
  ]);
  static const load = PixelGlyph([
    '....#....',
    '....#....',
    '....#....',
    '..#.#.#..',
    '...###...',
    '....#....',
    '#.......#',
    '#.......#',
    '#########',
  ]);
  static const key = PixelGlyph([
    '.........',
    '.###.....',
    '#...#....',
    '#.+.#####',
    '#...#.#.#',
    '.###..#.#',
    '.........',
    '.........',
    '.........',
  ]);
  static const camera = PixelGlyph([
    '.........',
    '..###....',
    '#########',
    '#..###..#',
    '#.#+++#.#',
    '#.#+++#.#',
    '#..###..#',
    '#########',
    '.........',
  ]);
  static const fast = PixelGlyph([
    '.........',
    '#...#....',
    '##..##...',
    '###.###..',
    '########.',
    '###.###..',
    '##..##...',
    '#...#....',
    '.........',
  ]);
  static const power = PixelGlyph([
    '....#....',
    '.#..#..#.',
    '#...#...#',
    '#...#...#',
    '#.......#',
    '#.......#',
    '.#.....#.',
    '..#####..',
    '.........',
  ]);
  static const star = PixelGlyph([
    '....#....',
    '....#....',
    '...###...',
    '#########',
    '.#######.',
    '..#####..',
    '..##.##..',
    '.##...##.',
    '.#.....#.',
  ]);
  static const trophy = PixelGlyph([
    '#########',
    '#.#####.#',
    '#.##+##.#',
    '.#.###.#.',
    '...###...',
    '....#....',
    '....#....',
    '..#####..',
    '..#####..',
  ]);
  static const box = PixelGlyph([
    '..#######',
    '.#.....##',
    '#######.#',
    '#.....#.#',
    '#.+++.#.#',
    '#.+++.#.#',
    '#.....#.#',
    '#.....##.',
    '#######..',
  ]);
  static const search = PixelGlyph([
    '.####....',
    '#....#...',
    '#.++.#...',
    '#.+..#...',
    '#....#...',
    '.#####...',
    '.....##..',
    '......##.',
    '.......##',
  ]);
  static const back = PixelGlyph([
    '.........',
    '...#.....',
    '..##.....',
    '.########',
    '#########',
    '.########',
    '..##.....',
    '...#.....',
    '.........',
  ]);
  static const palette = PixelGlyph([
    '..#####..',
    '.#.....#.',
    '#.##.##.#',
    '#.##.##.#',
    '#.......#',
    '#.##...#.',
    '#.##..#..',
    '.#...#...',
    '..###....',
  ]);
  static const home = PixelGlyph([
    '....#....',
    '...###...',
    '..##.##..',
    '.##...##.',
    '##.....##',
    '.#.###.#.',
    '.#.#.#.#.',
    '.#.#.#.#.',
    '.#######.',
  ]);
  static const info = PixelGlyph([
    '..#####..',
    '.#..#..#.',
    '#.......#',
    '#...#...#',
    '#...#...#',
    '#...#...#',
    '#...#...#',
    '.#.....#.',
    '..#####..',
  ]);
  static const trash = PixelGlyph([
    '...###...',
    '#########',
    '.#.....#.',
    '.#.#.#.#.',
    '.#.#.#.#.',
    '.#.#.#.#.',
    '.#.#.#.#.',
    '.#.....#.',
    '.#######.',
  ]);
  static const pencil = PixelGlyph([
    '......##.',
    '.....#.##',
    '....#.##.',
    '...#.##..',
    '..#.##...',
    '.#.##....',
    '#.##.....',
    '##.......',
    '###......',
  ]);
  static const picture = PixelGlyph([
    '#########',
    '#.......#',
    '#.##....#',
    '#.##....#',
    '#....#..#',
    '#...###.#',
    '#.#+####+',
    '#########',
    '.........',
  ]);
  static const tv = PixelGlyph([
    '..#...#..',
    '...#.#...',
    '#########',
    '#.......#',
    '#.+++++.#',
    '#.+++++.#',
    '#.......#',
    '#########',
    '.##...##.',
  ]);
  static const speaker = PixelGlyph([
    '....#....',
    '...##..#.',
    '####.#..#',
    '#...#.#.#',
    '#...#.#.#',
    '####.#..#',
    '...##..#.',
    '....#....',
    '.........',
  ]);
  static const bolt = PixelGlyph([
    '.....##..',
    '....##...',
    '...##....',
    '..######.',
    '.....##..',
    '....##...',
    '...##....',
    '..##.....',
    '.#.......',
  ]);
  static const pad = PixelGlyph([
    '.........',
    '.#######.',
    '#.#.....#',
    '###...#.#',
    '#.#..#.##',
    '#.....#.#',
    '.#######.',
    '.#.....#.',
    '.........',
  ]);
  static const wifi = PixelGlyph([
    '.........',
    '.#######.',
    '#.......#',
    '..#####..',
    '.#.....#.',
    '...###...',
    '..#...#..',
    '....#....',
    '....#....',
  ]);
  static const folder = PixelGlyph([
    '.........',
    '###......',
    '#..####..',
    '#######.#',
    '#.......#',
    '#.......#',
    '#.......#',
    '#########',
    '.........',
  ]);
  static const plus = PixelGlyph([
    '.........',
    '....#....',
    '....#....',
    '....#....',
    '#########',
    '....#....',
    '....#....',
    '....#....',
    '.........',
  ]);
  static const shuffle = PixelGlyph([
    '......#..',
    '##...####',
    '..#.#..#.',
    '...#.....',
    '...#.....',
    '..#.#..#.',
    '##...####',
    '......#..',
    '.........',
  ]);
  static const clock = PixelGlyph([
    '..#####..',
    '.#..#..#.',
    '#...#...#',
    '#...#...#',
    '#...###.#',
    '#.......#',
    '#.......#',
    '.#.....#.',
    '..#####..',
  ]);
  static const rewind = PixelGlyph([
    '.........',
    '....#...#',
    '...##..##',
    '..###.###',
    '.########',
    '..###.###',
    '...##..##',
    '....#...#',
    '.........',
  ]);
  static const link = PixelGlyph([
    '.........',
    '.###.....',
    '#...#....',
    '#.+.#....',
    '.####+###',
    '....#.+.#',
    '....#...#',
    '.....###.',
    '.........',
  ]);
  static const cursor = PixelGlyph([
    '.........',
    '.#.......',
    '.##......',
    '.###.....',
    '.####....',
    '.###.....',
    '.##......',
    '.#.......',
    '.........',
  ]);
}

/// [glyph] drawn with square cells, [size] logical pixels wide. Ink comes
/// from [color] or the icon theme; the mid shade is the palette's dark tone
/// (or [color] faded when there is no Pocket theme).
class PixelIcon extends StatelessWidget {
  const PixelIcon(this.glyph, {super.key, this.size, this.color, this.label});

  final PixelGlyph glyph;
  final double? size;
  final Color? color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    final s = size ?? icon.size ?? 18;
    final ink = color ?? icon.color ?? Theme.of(context).colorScheme.onSurface;
    final mid = Color.lerp(ink, PocketStyle.of(context).palette.light, 0.55)!;
    final paint = SizedBox.square(
      dimension: s,
      child: CustomPaint(painter: _GlyphPainter(glyph, ink, mid)),
    );
    return label == null
        ? ExcludeSemantics(child: paint)
        : Semantics(label: label, child: paint);
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.ink, this.mid);

  final PixelGlyph glyph;
  final Color ink, mid;

  @override
  void paint(Canvas canvas, Size size) {
    // Whole device pixels per cell where possible, centred.
    final cell = (size.shortestSide / 9).floorToDouble().clamp(1.0, 99.0);
    final origin = Offset(
      ((size.width - cell * 9) / 2).roundToDouble(),
      ((size.height - cell * 9) / 2).roundToDouble(),
    );
    final inkPaint = Paint()..color = ink;
    final midPaint = Paint()..color = mid;
    for (var y = 0; y < glyph.rows.length; y++) {
      final row = glyph.rows[y];
      for (var x = 0; x < row.length; x++) {
        final c = row[x];
        if (c != '#' && c != '+') continue;
        canvas.drawRect(
          origin + Offset(x * cell, y * cell) & Size.square(cell),
          c == '#' ? inkPaint : midPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.ink != ink || old.mid != mid;
}
