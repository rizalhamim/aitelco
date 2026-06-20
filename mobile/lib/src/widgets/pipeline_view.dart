import 'package:flutter/material.dart';
import '../api/models.dart';
import '../theme.dart';

/// Agent pipeline. Default collapsed: shows only the currently-running (or last)
/// step. Expanded: shows the full step list.
class PipelineView extends StatefulWidget {
  final List<FlowStep> steps;
  final bool live;
  final int? tokens;
  const PipelineView({super.key, required this.steps, required this.live, this.tokens});

  @override
  State<PipelineView> createState() => _PipelineViewState();
}

class _PipelineViewState extends State<PipelineView> {
  bool _expanded = false;

  Color _kindColor(String k) {
    switch (k) {
      case 'router': return IOH.pink;
      case 'analyst': return const Color(0xFFFF6B35);
      case 'sql_write': return IOH.yellow;
      case 'bq_exec': return IOH.teal;
      case 'synth': return IOH.magenta;
      case 'scope': return IOH.pink;
      case 'reroute': return const Color(0xFFFF6B35);
      case 'reflect': return const Color(0xFF22A85A);
      case 'retry': return IOH.yellow;
      case 'done': return IOH.teal;
      case 'error': return IOH.danger;
      default: return IOH.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final running = steps.lastWhere((s) => !s.done, orElse: () => steps.last);
    final shown = _expanded ? steps : [running];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF15151A), Color(0xFF0B0B0E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('AGENT PIPELINE',
                style: TextStyle(fontFamily: 'Poppins', color: IOH.yellow, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const Spacer(),
            if (widget.tokens != null && widget.tokens! > 0)
              Padding(padding: const EdgeInsets.only(right: 8),
                  child: Text('${widget.tokens} tok', style: const TextStyle(color: IOH.yellow, fontSize: 11, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (widget.live ? IOH.yellow : IOH.teal).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(widget.live ? 'LIVE' : 'DONE',
                  style: TextStyle(color: widget.live ? IOH.yellow : IOH.teal, fontSize: 9, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Icon(_expanded ? Icons.unfold_less : Icons.unfold_more, color: Colors.white70, size: 18),
            ),
          ]),
          const SizedBox(height: 10),
          for (int i = 0; i < shown.length; i++)
            _step(shown[i], !shown[i].done && widget.live),
          if (!_expanded && steps.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+${steps.length - 1} langkah · ketuk ikon untuk lihat semua',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
            ),
        ],
      ),
    );
  }

  Widget _step(FlowStep s, bool active) {
    final color = _kindColor(s.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: const Color(0xFF0C0C0E), borderRadius: BorderRadius.circular(8), border: Border.all(color: color, width: 2)),
          child: active
              ? const Padding(padding: EdgeInsets.all(7), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(s.done ? Icons.check : Icons.bolt, color: color, size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.label, style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          if (s.feedback != null && s.feedback!.isNotEmpty)
            Text(s.feedback!, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}
