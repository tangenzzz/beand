import 'parsing_utils.dart';

// Raw sensors from the `sensors` event. Field names verified live against
// the real machine — they differ from the original API docs (e.g.
// `t_bar_up` instead of `bar_up`, `t_bar_mu`/`t_bar_md` instead of
// `bar_mid_up`/`bar_mid_down`). No `motor_thermistor` field observed.
//
// Physical mapping of the 4 "bar" sensors:
// barUp = brew chamber top, barMidUp = brew chamber middle,
// barMidDown = brew chamber bottom, barDown = brew head.
// Matches the display order in TemperatureTile (left -> right).
class MachineSensors {
  final double externalTemp1;
  final double externalTemp2;
  final double barUp;
  final double barMidUp;
  final double barMidDown;
  final double barDown;
  final double tubeTemp;
  final double motorTemp;
  final double lamTemp;
  final double pressureRaw;
  final double motorPosition;
  final double motorSpeed;
  final double motorPower;
  final double motorCurrent;
  final double bandheaterPower;
  final double bandheaterCurrent;
  final bool waterStatus;
  final double weightPrediction;

  const MachineSensors({
    required this.externalTemp1,
    required this.externalTemp2,
    required this.barUp,
    required this.barMidUp,
    required this.barMidDown,
    required this.barDown,
    required this.tubeTemp,
    required this.motorTemp,
    required this.lamTemp,
    required this.pressureRaw,
    required this.motorPosition,
    required this.motorSpeed,
    required this.motorPower,
    required this.motorCurrent,
    required this.bandheaterPower,
    required this.bandheaterCurrent,
    required this.waterStatus,
    required this.weightPrediction,
  });

  factory MachineSensors.fromJson(Map<String, dynamic> json) {
    return MachineSensors(
      externalTemp1: parseDouble(json['t_ext_1']),
      externalTemp2: parseDouble(json['t_ext_2']),
      barUp: parseDouble(json['t_bar_up']),
      barMidUp: parseDouble(json['t_bar_mu']),
      barMidDown: parseDouble(json['t_bar_md']),
      barDown: parseDouble(json['t_bar_down']),
      tubeTemp: parseDouble(json['t_tube']),
      motorTemp: parseDouble(json['t_motor_temp']),
      lamTemp: parseDouble(json['lam_temp']),
      pressureRaw: parseDouble(json['p']),
      motorPosition: parseDouble(json['m_pos']),
      motorSpeed: parseDouble(json['m_spd']),
      motorPower: parseDouble(json['m_pwr']),
      motorCurrent: parseDouble(json['m_cur']),
      bandheaterPower: parseDouble(json['bh_pwr']),
      bandheaterCurrent: parseDouble(json['bh_cur']),
      waterStatus: json['w_stat'] as bool? ?? false,
      weightPrediction: parseDouble(json['weight_pred']),
    );
  }
}
