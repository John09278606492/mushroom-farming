import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../logic/alerts.dart';

const _seed = Color(0xFF4F7A3A); // moss green

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: const CardThemeData(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}

/// Status colors that work in light and dark mode.
extension SeverityColors on Severity {
  Color color(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      Severity.ok => dark ? const Color(0xFF7BD88F) : const Color(0xFF2E7D32),
      Severity.info => dark ? const Color(0xFF8AB4F8) : const Color(0xFF1565C0),
      Severity.warning => dark ? const Color(0xFFFFC266) : const Color(0xFFB26A00),
      Severity.critical => dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
    };
  }

  Color background(BuildContext context) =>
      color(context).withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10);

  IconData get icon => switch (this) {
        Severity.ok => Icons.check_circle,
        Severity.info => Icons.info,
        Severity.warning => Icons.warning_amber_rounded,
        Severity.critical => Icons.error,
      };
}

String timeAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds} s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

String formatClock(int hour, int minute) =>
    DateFormat.jm().format(DateTime(2000, 1, 1, hour, minute));

String formatDateTime(DateTime t) => DateFormat('MMM d, h:mm a').format(t);

String formatDate(DateTime t) => DateFormat('MMM d, yyyy').format(t);

/// Section header used on list pages.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
