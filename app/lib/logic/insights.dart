// The room summary on the home screen: a health score and short, plain-language
// tips built from the live readings. Rule-based (no AI model), pure, tested.

import '../models/farm_models.dart';
import 'alerts.dart';

class FarmInsight {
  const FarmInsight({
    required this.score,
    required this.headline,
    required this.tips,
    required this.mood,
  });

  /// 0–100, or null when there is no fresh data to judge.
  final int? score;
  final String headline;
  final List<String> tips;
  final Severity mood;
}

const maxInsightTips = 3;

FarmInsight computeInsight(LiveData live, Setpoints sp, DateTime now, {Batch? openBatch}) {
  if (!live.hasData) {
    return const FarmInsight(
      score: null,
      headline: 'Waiting for the controller to connect',
      tips: ['Power on the ESP32 controller and the pocket WiFi.'],
      mood: Severity.info,
    );
  }
  if (!live.isOnline(now)) {
    return const FarmInsight(
      score: null,
      headline: 'The controller is not reachable',
      tips: [
        'The farm keeps running on its own rules.',
        'Check the pocket WiFi load and the controller power.',
      ],
      mood: Severity.critical,
    );
  }

  var score = 100.0;
  final tips = <String>[];
  final rh = live.rh;
  final co2 = live.co2;
  final t = live.temp;

  if (live.waterCutoff == true) {
    score -= 30;
    tips.add('The water tank is empty, so the pumps are stopped. Refill it now.');
  } else if (live.lowWater) {
    score -= 10;
    tips.add(live.deviceOn(DeviceId.refill)
        ? 'Water is low. The refill pump is topping up the tank.'
        : 'Water is low. Refill the tank or turn on the refill pump.');
  }

  if (rh == null) {
    score -= 15;
    tips.add('No humidity reading. Check the humidity sensor wiring.');
  } else if (rh < sp.humOn) {
    score -= ((sp.humOn - rh) * 3).clamp(0, 30);
    tips.add(live.deviceOn(DeviceId.mist)
        ? 'Humidity is ${rh.toStringAsFixed(0)}%. The mist maker is raising it to ${sp.humOn.toStringAsFixed(0)}%.'
        : 'Humidity is ${rh.toStringAsFixed(0)}%, below ${sp.humOn.toStringAsFixed(0)}%. Turn on the mist maker or use Auto.');
  } else if (rh > sp.humOff + 2) {
    score -= ((rh - sp.humOff) * 3).clamp(0, 15);
    tips.add('Humidity is ${rh.toStringAsFixed(0)}%. Too wet can cause water spots on the caps.');
  }

  if (co2 == null) {
    score -= 15;
    tips.add('No CO2 reading. Check the CO2 sensor wiring.');
  } else if (co2 > sp.co2On) {
    score -= ((co2 - sp.co2On) / 20).clamp(0, 30);
    tips.add(live.deviceOn(DeviceId.fan)
        ? 'CO2 is $co2 ppm. The exhaust fan is clearing it.'
        : 'CO2 is $co2 ppm. Turn on the exhaust fan for fresh air.');
  }

  if (t != null && t > sp.tempMax) {
    score -= ((t - sp.tempMax) * 5).clamp(0, 25);
    tips.add('It is ${t.toStringAsFixed(1)} °C, above ${sp.tempMax.toStringAsFixed(0)} °C. Add shade or airflow.');
  } else if (t != null && t < sp.tempMin) {
    score -= ((sp.tempMin - t) * 5).clamp(0, 25);
    tips.add('It is ${t.toStringAsFixed(1)} °C, below ${sp.tempMin.toStringAsFixed(0)} °C. Keep the room closed and warm.');
  }

  if (live.mode == FarmMode.manual) {
    tips.add('Manual mode is on. Switch back to Auto when you are done.');
  }

  if (openBatch != null) {
    final day = openBatch.dayNumber(now);
    tips.add(day < 5
        ? 'Batch is on day $day. Harvest is usually around day 5–7.'
        : day <= 7
            ? 'Batch is on day $day: the harvest window is open.'
            : 'Batch is on day $day. Harvest today before the caps curl up.');
  }

  final s = score.round().clamp(0, 100);
  final stage = sp.stage.label.toLowerCase();
  final headline = s >= 85
      ? 'Conditions are ideal for $stage'
      : s >= 60
          ? 'Mostly good, a few things need attention'
          : 'The grow room needs attention now';
  if (tips.isEmpty) tips.add('All readings are inside your targets.');

  return FarmInsight(
    score: s,
    headline: headline,
    tips: tips.take(maxInsightTips).toList(),
    mood: s >= 85
        ? Severity.ok
        : s >= 60
            ? Severity.warning
            : Severity.critical,
  );
}
