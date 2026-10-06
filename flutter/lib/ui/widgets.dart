// Small building blocks shared by the screens.
import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Indeterminate ring (the prototype's `.spin`).
class Spinner extends StatelessWidget {
  const Spinner({super.key, this.size = 14, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: color ?? DefaultTextStyle.of(context).style.color,
    ),
  );
}

/// The `@` / `#` marker of a room.
class RoomMark extends StatelessWidget {
  const RoomMark({
    super.key,
    required this.isDirect,
    this.selected = false,
    this.size = 26,
  });

  final bool isDirect;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? c.accent : c.surface,
        borderRadius: BorderRadius.circular(size > 28 ? 9 : 7),
        border: Border.all(color: selected ? c.accent : c.line2),
      ),
      child: Text(
        isDirect ? '@' : '#',
        style: TextStyle(
          fontFamily: monoFont,
          fontSize: size > 28 ? 14 : 12,
          fontWeight: FontWeight.w600,
          color: selected ? c.accentInk : c.text2,
        ),
      ),
    );
  }
}

/// Shows [child] only after [delay], to avoid flashing short states.
class DelayedVisibility extends StatefulWidget {
  const DelayedVisibility({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 300),
  });

  final Widget child;
  final Duration delay;

  @override
  State<DelayedVisibility> createState() => _DelayedVisibilityState();
}

class _DelayedVisibilityState extends State<DelayedVisibility> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () => setState(() => _visible = true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _visible ? widget.child : const SizedBox.shrink();
}

/// Placeholder bar while content loads.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    required this.height,
    this.width,
    this.widthFactor,
    this.radius = 14,
  });

  final double height;
  final double? width;
  final double? widthFactor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppColors.of(context).hover,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return widthFactor == null
        ? box
        : FractionallySizedBox(widthFactor: widthFactor, child: box);
  }
}

/// Centered icon, title and text (empty, error and neutral states).
class NeutralState extends StatelessWidget {
  const NeutralState({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.error = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String text;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: error ? c.errBg : c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: error ? Colors.transparent : c.line),
              ),
              child: Icon(icon, size: 24, color: error ? c.errInk : c.text2),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: c.text2),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// The prototype's `.btn.pri` / `.btn.sec`.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
    this.icon,
    this.height = 38,
    this.fontSize = 14,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final Widget? icon;
  final double height;
  final double fontSize;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final enabled = onPressed != null;
    final background = !enabled
        ? c.hover
        : primary
        ? c.accent
        : c.surface;
    final foreground = !enabled
        ? c.text2
        : primary
        ? c.accentInk
        : c.text;
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background,
          disabledForegroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(height >= 44 ? 9 : 8),
            side: primary || !enabled
                ? BorderSide.none
                : BorderSide(color: c.line2),
          ),
          textStyle: TextStyle(
            fontFamily: sansFont,
            fontWeight: FontWeight.w600,
            fontSize: fontSize,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 8)],
            Text(label),
          ],
        ),
      ),
    );
  }
}

enum AlertKind { error, info, warning }

/// Inline alert box (login alerts, composer notice).
class AlertBox extends StatelessWidget {
  const AlertBox({
    super.key,
    required this.kind,
    required this.title,
    required this.text,
    this.action,
    this.onClose,
  });

  final AlertKind kind;
  final String title;
  final String text;
  final Widget? action;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (background, foreground) = switch (kind) {
      AlertKind.error => (c.errBg, c.errInk),
      AlertKind.info => (c.infoBg, c.infoInk),
      AlertKind.warning => (c.warnBg, c.warnInk),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: sansFont,
            fontSize: 13.5,
            height: 1.45,
            color: foreground,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline, size: 18, color: foreground),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(text),
                    ?action,
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  tooltip: 'Fechar aviso',
                  icon: Icon(Icons.close, size: 16, color: foreground),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Underlined inline action inside an alert ("Tentar de novo").
class InlineAction extends StatelessWidget {
  const InlineAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          color: DefaultTextStyle.of(context).style.color,
        ),
      ),
    ),
  );
}
