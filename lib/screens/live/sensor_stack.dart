import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'temperature_ring.dart';

// The sensor/value column to the right of the hero ring — the same for
// BOTH machines.
//
// A row is: a vertical color mark in the value's curve color, next to it
// the label and below it the value. No border, no fill — color is carried
// by the mark alone, the value stays in the text color and is as readable
// as the rest.
//
// The Meticulous fills it with its four sensors, the GaggiMate with
// pressure, flow and weight. If a value is missing, the row stays in both
// cases and shows "—": shape and height of the column must not jump when a
// scale is added or a sensor goes silent.
class SensorValue {
  const SensorValue(
    this.code,
    this.value,
    this.color, {
    this.unit = '',
    this.digits = 1,
    this.text,
  });

  final String code;
  final double? value;
  final Color color;
  // Sits directly after the value ('°' for temperatures). Empty where the
  // label already names the unit (BAR, ML/S, G).
  final String unit;
  final int digits;
  // Preformatted value instead of a number (e.g. a time "1:42" for
  // Pour Over); takes precedence over [value] + [digits].
  final String? text;
}

// The values stacked next to the ring. The column is never taller than the
// ring — the rows are tightly spaced and sit together on its center.
class SensorStack extends StatelessWidget {
  const SensorStack({
    super.key,
    required this.sensors,
    this.dimMissing = false,
  });

  final List<SensorValue> sensors;

  // Additionally dim a row without a value. Only the GaggiMate does this:
  // there a missing value means "the machine can't" (pressure/flow only on
  // the Pro, weight only with a scale), and that should be visible. On the
  // Meticulous values are only missing while there is no data yet — the
  // column stays unchanged there.
  final bool dimMissing;

  // Gap between two rows. Together with the fixed row heights in
  // [SensorRow] this keeps the column safely below defaultSize — otherwise
  // it would overtop the ring instead of following it.
  static const _gap = 10.0;

  // Room between ring and column, and fixed column width. Fixed rather than
  // content-sized, so the group stays centered and does not jump when a
  // value gets three digits.
  static const ringToValues = 30.0;
  static const _width = 92.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: TemperatureRing.defaultSize,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < sensors.length; i++) ...[
            if (i > 0) const SizedBox(height: _gap),
            SensorRow(sensors[i], dimMissing: dimMissing),
          ],
        ],
      ),
    );
  }
}

class SensorRow extends StatelessWidget {
  const SensorRow(this.data, {super.key, this.dimMissing = false});

  final SensorValue data;
  final bool dimMissing;

  // Row heights fixed instead of left to the font: only then can we
  // compute that the column fits within the ring.
  static const _labelHeight = 1.2;
  static const _valueHeight = 1.15;

  @override
  Widget build(BuildContext context) {
    final missing = data.value == null && data.text == null;
    return Opacity(
      opacity: missing && dimMissing ? 0.45 : 1,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Color mark next to the name/value pair.
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: data.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 10,
                    height: _labelHeight,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  missing
                      ? '—'
                      : data.text ??
                            '${data.value!.toStringAsFixed(data.digits)}${data.unit}',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 15,
                    height: _valueHeight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
