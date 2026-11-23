import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../machines/espresso_machine.dart';
import '../../../scale/bluetooth_prompt.dart';
import '../../../scale/brew_scale.dart';
import '../../../sensors/pressure_sensor.dart';
import '../../../services/espresso_shot_service.dart';
import '../../../services/live_shot_service.dart';
import '../../../services/shot_setup.dart';
import '../../../theme/app_theme.dart';
import '../../root_scaffold.dart';
import '../../settings/scale_settings_screen.dart';
import '../pourover/pourover_command_row.dart' show CommandRowButton;
import '../pourover/recipe_format.dart';
import '../sensor_stack.dart';
import '../shot_cards_carousel.dart';
import '../temperature_ring.dart';

// Home → Espresso: an espresso machine the app does not talk to. Shots are
// logged by hand in the same Pre/Live/Post cards as on the machines; a
// Bluetooth scale and a pressure sensor (Pressensor) are optional and only
// add their curves. No profiles.
class EspressoHome extends StatelessWidget {
  const EspressoHome({super.key});

  // One stand-in for the app's lifetime: the cards only ask it for its key
  // and its (empty) profiles.
  static final _machine = ManualEspressoMachine();

  @override
  Widget build(BuildContext context) {
    final service = context.read<EspressoShotService>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EspressoMachine>.value(value: _machine),
        ChangeNotifierProvider<LiveShotService>.value(value: service),
        ChangeNotifierProvider<ShotSetup>.value(value: service.setup),
        // The Bluetooth scale, never the Meticulous' built-in one.
        ChangeNotifierProvider<BrewScale>.value(value: service.scale),
      ],
      child: const _Body(),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  @override
  void initState() {
    super.initState();
    // As in Pour Over: a known scale connects when the view opens.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final scale = context.read<EspressoShotService>().scale;
      if (scale.connection == ScaleConnection.disconnected &&
          scale.error == null &&
          scale.rememberedId != null) {
        if (!await ensureBluetoothOn(context, scale)) return;
        unawaited(scale.connect());
      }
      if (!mounted) return;
      final sensor = context.read<PressureSensor>();
      if (sensor.connection == ScaleConnection.disconnected &&
          sensor.error == null &&
          sensor.rememberedId != null) {
        unawaited(sensor.connect());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EspressoHero(),
        _EspressoCommandRow(),
        SizedBox(height: 12),
        // The Pre card without its Profile row (one row less).
        ShotCardsCarousel(extraCardHeight: ShotCardsCarousel.machineExtra),
      ],
    );
  }
}

// ---- Hero ----------------------------------------------------------------

// Ring on the left, time and weight on the right as in Pour Over (plus the
// pressure once a sensor is connected).
//
// The ring is a first take (what it should show is still open): it fills
// toward the target yield (dose × 2) with a scale, otherwise toward 30 s.
class _EspressoHero extends StatelessWidget {
  const _EspressoHero();

  static const _ringSize = TemperatureRing.defaultSize + 8;
  static const _defaultRatio = 2.0;
  static const _defaultSeconds = 30.0;

  @override
  Widget build(BuildContext context) {
    final shot = context.watch<EspressoShotService>();
    final scale = shot.scale;
    final sensor = shot.sensor;
    final running = shot.stage == ShotStage.running;
    final done = shot.activeCard == ActiveCard.post;
    final seconds = shot.elapsedMs / 1000;
    final grams = shot.grams;
    final dose = shot.setup.doseGrams;
    final targetYield = dose == null ? null : dose * _defaultRatio;

    final weighs = scale.isConnected && targetYield != null;
    final double progress = !running && !done
        ? 0
        : weighs
        ? ((grams ?? 0) / targetYield).clamp(0.0, 1.0)
        : (seconds / _defaultSeconds).clamp(0.0, 1.0);

    final String label = running
        ? 'SHOT'
        : done
        ? 'DONE'
        : 'READY';
    final String line = weighs && (running || done)
        ? '1:${((grams ?? 0) / dose!).toStringAsFixed(1)}'
        : '${seconds.toStringAsFixed(seconds < 100 ? 1 : 0)} s';
    final String? detail = weighs
        ? 'of ${formatGrams(targetYield)} g'
        : scale.isConnected
        ? null
        : 'No scale';

    final values = <SensorValue>[
      SensorValue(
        'TIME',
        null,
        context.colors.textPrimary,
        text: formatClock(seconds),
      ),
      SensorValue('G', grams, context.colors.sensorMid),
      if (sensor.isConnected)
        SensorValue('BAR', sensor.bar, context.colors.success),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: _ringSize,
                height: _ringSize,
                child: CustomPaint(
                  painter: _RingPainter(
                    progress: progress,
                    track: context.colors.divider,
                    color: context.colors.accent,
                  ),
                  child: _RingText(label: label, line: line, detail: detail),
                ),
              ),
              const SizedBox(width: SensorStack.ringToValues),
              SensorStack(sensors: values, large: true),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 20,
            child: shot.lastError == null
                ? null
                : Center(
                    child: Text(
                      shot.lastError!,
                      style: TextStyle(
                        color: context.colors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RingText extends StatelessWidget {
  const _RingText({required this.label, required this.line, this.detail});

  final String label;
  final String line;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            line,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.track,
    required this.color,
  });

  final double progress;
  final Color track;
  final Color color;

  static const _stroke = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - _stroke,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.track != track || old.color != color;
}

// ---- Command row ---------------------------------------------------------

// Same shape as on the other homes: Tare, the Bluetooth scale (name and
// battery) and the pressure sensor (connect / name and battery). A long
// press on the scale opens Settings → Scales; on the sensor it forgets it.
class _EspressoCommandRow extends StatelessWidget {
  const _EspressoCommandRow();

  @override
  Widget build(BuildContext context) {
    final shot = context.watch<EspressoShotService>();
    final scale = context.watch<BrewScale>();
    final sensor = context.watch<PressureSensor>();
    final locked = shot.stage == ShotStage.running;

    final battery = scale.batteryPercent;
    final (IconData scaleIcon, String scaleLabel) = switch (scale.connection) {
      ScaleConnection.connected => (
        Icons.bluetooth_connected,
        battery == null ? scale.shortName : '${scale.shortName} $battery%',
      ),
      ScaleConnection.scanning ||
      ScaleConnection.connecting => (Icons.bluetooth_searching, 'Searching'),
      ScaleConnection.disconnected =>
        scale.error != null
            ? (Icons.bluetooth_disabled, 'No scale')
            : (Icons.bluetooth, 'Scale'),
    };

    final sensorBattery = sensor.batteryPercent;
    final lowSensorBattery =
        sensor.isConnected && sensorBattery != null && sensorBattery <= 15;
    final String sensorLabel = switch (sensor.connection) {
      ScaleConnection.connected =>
        sensorBattery == null
            ? sensor.shortName
            : '${sensor.shortName} $sensorBattery%',
      ScaleConnection.scanning || ScaleConnection.connecting => 'Searching',
      ScaleConnection.disconnected =>
        sensor.error != null ? 'No sensor' : 'Sensor',
    };

    final buttons = <Widget>[
      CommandRowButton(
        icon: Icons.balance,
        label: 'Tare',
        onTap: scale.isConnected ? shot.tare : null,
      ),
      CommandRowButton(
        icon: scaleIcon,
        iconColor: battery != null && battery <= 15
            ? context.colors.danger
            : null,
        label: scaleLabel,
        onTap: locked
            ? null
            : scale.connection == ScaleConnection.disconnected
            ? () => _connectScale(context, scale)
            : () => _openScaleSettings(context),
        onLongPress: () => _openScaleSettings(context),
      ),
      CommandRowButton(
        icon: Icons.speed,
        iconColor: lowSensorBattery ? context.colors.danger : null,
        // The maker's logo (with permission): in its colours while
        // connected, grey like the other icons otherwise (user 2026-11-23).
        iconWidget: sensor.logoAsset == null
            ? null
            : SensorLogo(
                asset: sensor.logoAsset!,
                colored: sensor.isConnected && !lowSensorBattery,
              ),
        label: sensorLabel,
        onTap: locked
            ? null
            : switch (sensor.connection) {
                ScaleConnection.disconnected => () => _connectSensor(
                  context,
                  scale,
                  sensor,
                ),
                ScaleConnection.connected => () => _sensorMenu(context, sensor),
                _ => null,
              },
        onLongPress: locked || sensor.rememberedId == null
            ? null
            : () => _sensorMenu(context, sensor),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: context.colors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: buttons,
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
        ],
      ),
    );
  }

  static Future<void> _connectScale(
    BuildContext context,
    BrewScale scale,
  ) async {
    // No scale known yet: the scale page has the search.
    if (scale.rememberedId == null) {
      _openScaleSettings(context);
      return;
    }
    if (!await ensureBluetoothOn(context, scale)) return;
    unawaited(scale.connect());
  }

  static Future<void> _connectSensor(
    BuildContext context,
    BrewScale scale,
    PressureSensor sensor,
  ) async {
    // Same Bluetooth prompt as for the scale.
    if (!await ensureBluetoothOn(context, scale)) return;
    await sensor.connect();
    if (!context.mounted || sensor.error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sensor.error!),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static Future<void> _sensorMenu(
    BuildContext context,
    PressureSensor sensor,
  ) async {
    final colors = context.colors;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.tile),
        ),
      ),
      builder: (context) {
        Widget option(String value, IconData icon, String title) => ListTile(
          leading: Icon(icon, color: colors.textSecondary),
          title: Text(title, style: TextStyle(color: colors.textPrimary)),
          onTap: () => Navigator.pop(context, value),
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  (sensor.deviceName ?? 'PRESSURE SENSOR').toUpperCase(),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (sensor.isConnected) ...[
                option('zero', Icons.exposure_zero, 'Set zero'),
                option('disconnect', Icons.link_off, 'Disconnect'),
              ],
              option('forget', Icons.delete_outline, 'Forget sensor'),
            ],
          ),
        );
      },
    );
    switch (choice) {
      case 'zero':
        await sensor.zero();
      case 'disconnect':
        await sensor.disconnect();
      case 'forget':
        await sensor.forget();
    }
  }

  static void _openScaleSettings(BuildContext context) {
    final nav = RootNavigation.maybeOf(context);
    if (nav?.openSettingsPage != null) {
      nav!.openSettingsPage!((_) => const ScaleSettingsScreen());
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ScaleSettingsScreen()),
      );
    }
  }
}

/// A sensor maker's logo in the command row: its own colours, or one colour
/// from the surrounding [IconTheme] (grey when not connected, red on a low
/// battery) — so it reads like the icons beside it.
class SensorLogo extends StatelessWidget {
  const SensorLogo({super.key, required this.asset, required this.colored});

  final String asset;
  final bool colored;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset,
      key: ValueKey(colored ? 'sensor-logo-colored' : 'sensor-logo-plain'),
      height: 24,
      filterQuality: FilterQuality.medium,
    );
    if (colored) return image;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        IconTheme.of(context).color ?? context.colors.textSecondary,
        BlendMode.srcIn,
      ),
      child: image,
    );
  }
}
