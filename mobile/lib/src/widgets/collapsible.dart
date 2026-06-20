import 'package:flutter/material.dart';
import '../theme.dart';

/// A show/hide section with a header bar. Default collapsed (per requirements).
class Collapsible extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;
  final bool initiallyExpanded;
  final String? badge;
  const Collapsible({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
    this.initiallyExpanded = false,
    this.badge,
  });

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: context.vWhite,
        border: Border.all(color: context.vRule),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                Icon(widget.icon, size: 17, color: widget.accent),
                const SizedBox(width: 9),
                Expanded(child: Text(widget.title,
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: context.vInk))),
                if (widget.badge != null)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: widget.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                    child: Text(widget.badge!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: widget.accent)),
                  ),
                Icon(_open ? Icons.expand_less : Icons.expand_more, color: context.vMute, size: 22),
              ]),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}
