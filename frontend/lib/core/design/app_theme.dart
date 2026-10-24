import 'package:flutter/material.dart';

class AppTheme {
  static const ink = Color(0xFF10182D);
  static const teal = Color(0xFF7045FF);
  static const muted = Color(0xFF858293);
  static const canvas = Color(0xFFF7F3FF);
  static const line = Color(0xFFEDE7F7);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamily: 'Poppins',
    textSelectionTheme: const TextSelectionThemeData(cursorColor: teal),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFFFCFAFF),
      indicatorColor: const Color(0xFFECE3FF),
      height: 76,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? teal : muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? teal : ink,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFFCFAFF),
      selectedColor: const Color(0xFFECE2FF),
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFFFCFAFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      surfaceTintColor: Colors.transparent,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: teal,
      primary: teal,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: canvas,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w700,
        letterSpacing: -.7,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFFCFAFF),
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFCFAFF),
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: line, thickness: 1),
  );
}

String human(Object? value) => (value ?? '')
    .toString()
    .replaceAll('_', ' ')
    .toLowerCase()
    .split(' ')
    .map((s) => s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}')
    .join(' ');
String person(Map? user) =>
    '${user?['firstName'] ?? ''} ${user?['lastName'] ?? ''}'.trim();
String dateLabel(Object? value) {
  final date = DateTime.tryParse('$value');
  if (date == null) return 'No date';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0B7850CB),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Material(
      color: const Color(0xFFFEFCFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: .9)),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final good = ['COMPLETED', 'APPROVED', 'ACTIVE'].contains(status);
    final bad = [
      'CANCELLED',
      'REJECTED',
      'SUSPENDED',
      'INACTIVE',
    ].contains(status);
    final color = good
        ? const Color(0xFF3DA45B)
        : bad
        ? const Color(0xFFBA4E47)
        : const Color(0xFF9C711F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        human(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
