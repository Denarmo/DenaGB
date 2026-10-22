// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:dena_emu/src/library/foil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('idle sweep glides across, then rests off the cover', () {
    expect(FoilTilt.sweepAt(0).dx, closeTo(-1.4, 1e-9));
    expect(FoilTilt.sweepAt(0.8).dx, closeTo(0, 1e-9));
    expect(FoilTilt.sweepAt(1.0).dx, greaterThan(FoilTilt.sweepAt(0.6).dx));
    // Resting: identical values, so covers do not repaint between passes.
    expect(FoilTilt.sweepAt(2), FoilTilt.sweepAt(5.9));
    expect(FoilTilt.sweepAt(2).dx, 1.4);
    // Next pass starts again from the far side.
    expect(FoilTilt.sweepAt(6).dx, closeTo(-1.4, 1e-9));
  });
}
