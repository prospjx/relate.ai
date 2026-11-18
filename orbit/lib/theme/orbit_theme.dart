import 'package:flutter/material.dart';

@immutable
class MessengerPalette extends ThemeExtension<MessengerPalette> {
  const MessengerPalette({
    required this.canvas,
    required this.surface,
    required this.hairline,
    required this.ink,
    required this.secondaryInk,
    required this.mutedInk,
    required this.accent,
    required this.outgoingBubble,
    required this.onOutgoingBubble,
    required this.incomingBubble,
    required this.onIncomingBubble,
    required this.avatarFill,
    required this.avatarInk,
    required this.online,
    required this.danger,
  });

  final Color canvas;
  final Color surface;
  final Color hairline;
  final Color ink;
  final Color secondaryInk;
  final Color mutedInk;
  final Color accent;
  final Color outgoingBubble;
  final Color onOutgoingBubble;
  final Color incomingBubble;
  final Color onIncomingBubble;
  final Color avatarFill;
  final Color avatarInk;
  final Color online;
  final Color danger;

  static const light = MessengerPalette(
    canvas: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F5F7),
    hairline: Color(0xFFE5E5EA),
    ink: Color(0xFF111114),
    secondaryInk: Color(0xFF6E6E73),
    mutedInk: Color(0xFF8E8E93),
    accent: Color(0xFF007AFF),
    outgoingBubble: Color(0xFF007AFF),
    onOutgoingBubble: Color(0xFFFFFFFF),
    incomingBubble: Color(0xFFEFEFF4),
    onIncomingBubble: Color(0xFF111114),
    avatarFill: Color(0xFFE5E5EA),
    avatarInk: Color(0xFF3A3A3C),
    online: Color(0xFF34C759),
    danger: Color(0xFFFF3B30),
  );

  static const dark = MessengerPalette(
    canvas: Color(0xFF0E0E10),
    surface: Color(0xFF1C1C1E),
    hairline: Color(0xFF2C2C2E),
    ink: Color(0xFFF2F2F7),
    secondaryInk: Color(0xFF98989F),
    mutedInk: Color(0xFF636366),
    accent: Color(0xFF0A84FF),
    outgoingBubble: Color(0xFF0A84FF),
    onOutgoingBubble: Color(0xFFFFFFFF),
    incomingBubble: Color(0xFF262629),
    onIncomingBubble: Color(0xFFF2F2F7),
    avatarFill: Color(0xFF2C2C2E),
    avatarInk: Color(0xFFEBEBF5),
    online: Color(0xFF30D158),
    danger: Color(0xFFFF453A),
  );

  static MessengerPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<MessengerPalette>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  MessengerPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? hairline,
    Color? ink,
    Color? secondaryInk,
    Color? mutedInk,
    Color? accent,
    Color? outgoingBubble,
    Color? onOutgoingBubble,
    Color? incomingBubble,
    Color? onIncomingBubble,
    Color? avatarFill,
    Color? avatarInk,
    Color? online,
    Color? danger,
  }) {
    return MessengerPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      hairline: hairline ?? this.hairline,
      ink: ink ?? this.ink,
      secondaryInk: secondaryInk ?? this.secondaryInk,
      mutedInk: mutedInk ?? this.mutedInk,
      accent: accent ?? this.accent,
      outgoingBubble: outgoingBubble ?? this.outgoingBubble,
      onOutgoingBubble: onOutgoingBubble ?? this.onOutgoingBubble,
      incomingBubble: incomingBubble ?? this.incomingBubble,
      onIncomingBubble: onIncomingBubble ?? this.onIncomingBubble,
      avatarFill: avatarFill ?? this.avatarFill,
      avatarInk: avatarInk ?? this.avatarInk,
      online: online ?? this.online,
      danger: danger ?? this.danger,
    );
  }

  @override
  MessengerPalette lerp(ThemeExtension<MessengerPalette>? other, double t) {
    if (other is! MessengerPalette) return this;
    return MessengerPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      secondaryInk: Color.lerp(secondaryInk, other.secondaryInk, t)!,
      mutedInk: Color.lerp(mutedInk, other.mutedInk, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      outgoingBubble: Color.lerp(outgoingBubble, other.outgoingBubble, t)!,
      onOutgoingBubble: Color.lerp(onOutgoingBubble, other.onOutgoingBubble, t)!,
      incomingBubble: Color.lerp(incomingBubble, other.incomingBubble, t)!,
      onIncomingBubble: Color.lerp(onIncomingBubble, other.onIncomingBubble, t)!,
      avatarFill: Color.lerp(avatarFill, other.avatarFill, t)!,
      avatarInk: Color.lerp(avatarInk, other.avatarInk, t)!,
      online: Color.lerp(online, other.online, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

ThemeData buildLightTheme() => _buildMessengerTheme(
      brightness: Brightness.light,
      palette: MessengerPalette.light,
    );

ThemeData buildDarkTheme() => _buildMessengerTheme(
      brightness: Brightness.dark,
      palette: MessengerPalette.dark,
    );

ThemeData _buildMessengerTheme({
  required Brightness brightness,
  required MessengerPalette palette,
}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
  );
  final textTheme = base.textTheme.apply(
    bodyColor: palette.ink,
    displayColor: palette.ink,
  );

  final colorScheme = (brightness == Brightness.dark
          ? const ColorScheme.dark()
          : const ColorScheme.light())
      .copyWith(
    primary: palette.accent,
    onPrimary: Colors.white,
    secondary: palette.accent,
    onSecondary: Colors.white,
    surface: palette.canvas,
    onSurface: palette.ink,
    onSurfaceVariant: palette.secondaryInk,
    surfaceContainerHighest: palette.surface,
    outline: palette.hairline,
    outlineVariant: palette.hairline,
    error: palette.danger,
    onError: Colors.white,
  );

  return base.copyWith(
    scaffoldBackgroundColor: palette.canvas,
    colorScheme: colorScheme,
    extensions: <ThemeExtension<dynamic>>[palette],
    textTheme: textTheme,
    dividerColor: palette.hairline,
    dividerTheme: DividerThemeData(
      color: palette.hairline,
      thickness: 1,
      space: 1,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.accent,
      selectionColor: palette.accent.withValues(alpha: 0.22),
      selectionHandleColor: palette.accent,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.canvas,
      foregroundColor: palette.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: palette.hairline, width: 1)),
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
      iconTheme: IconThemeData(color: palette.ink, size: 22),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: palette.ink,
      unselectedLabelColor: palette.secondaryInk,
      indicatorColor: palette.accent,
      dividerColor: palette.hairline,
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle:
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.canvas,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: palette.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.canvas,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.hairline),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor:
          brightness == Brightness.dark ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: palette.secondaryInk,
      textColor: palette.ink,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        side: BorderSide(color: palette.hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      hintStyle: TextStyle(color: palette.mutedInk, fontWeight: FontWeight.w400),
      labelStyle: TextStyle(color: palette.secondaryInk),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.danger, width: 1.5),
      ),
    ),
  );
}
