import 'package:flutter/material.dart';

import '../app/theme/app_colors.dart';

/// Plain, dependable scrolling: mouse wheel, trackpad, scrollbar drag and
/// keyboard all go through Flutter's own `Scrollable`, with a thin scrollbar
/// that shows while the pointer is over the view or the content is moving.
class AppScrollView extends StatefulWidget {
  const AppScrollView({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<AppScrollView> createState() => _AppScrollViewState();
}

class _AppScrollViewState extends State<AppScrollView> {
  final ScrollController _controller = ScrollController();
  bool _hover = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, overscroll: false),
        child: RawScrollbar(
          controller: _controller,
          thumbVisibility: _hover,
          thickness: 6,
          radius: const Radius.circular(3),
          thumbColor: c.textTertiary.withValues(alpha: _hover ? 0.55 : 0.35),
          minThumbLength: 28,
          padding: const EdgeInsets.fromLTRB(0, 4, 2, 4),
          interactive: true,
          child: SingleChildScrollView(
            controller: _controller,
            physics: const ClampingScrollPhysics(),
            padding: widget.padding,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
