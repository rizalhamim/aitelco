// Icon set of the approved Redesign v2 mockups (design/mockup-v2). Same SVG paths as the
// mockup sprite, drawn with flutter_svg, so screens match the mockup PNGs.
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

const Map<String, (String, String)> _icons = {
  'luser': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></g>'),
  'llock': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="11" width="16" height="10" rx="2.5"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></g>'),
  'leye': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></g>'),
  'leyeoff': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3l18 18M10.6 5.1A10.4 10.4 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4.2M6.6 6.6A17 17 0 0 0 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6M9.9 9.9a3 3 0 0 0 4.2 4.2"/></g>'),
  'pause': ('0 0 24 24', '<g fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1.2"/><rect x="14" y="5" width="4" height="14" rx="1.2"/></g>'),
  'play': ('0 0 24 24', '<path fill="currentColor" d="M8 5.5v13a1 1 0 0 0 1.5.9l10.4-6.5a1 1 0 0 0 0-1.7L9.5 4.6A1 1 0 0 0 8 5.5z"/>'),
  'arrowr': ('0 0 24 24', '<path d="M5 12h14M13 6l6 6-6 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'),
  'bars': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 20V11M10 20V5M15 20v-7M20 20V8"/></g>'),
  'bell': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9a6 6 0 0 1 12 0c0 6 2.5 7.5 2.5 7.5h-17S6 15 6 9z"/><path d="M10 20a2 2 0 0 0 4 0"/></g>'),
  'bellplus': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9a6 6 0 0 1 9-5.2M18 11c.3 4.4 2.5 5.5 2.5 5.5h-17S6 15 6 9"/><path d="M10 20a2 2 0 0 0 4 0M19 2v6M16 5h6"/></g>'),
  'cal': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/></g>'),
  'cam': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 8h3l1.5-2.5h7L17 8h3v11H4z"/><circle cx="12" cy="13" r="3.2"/></g>'),
  'chat': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/></g>'),
  'check': ('0 0 24 24', '<path d="m5 12.5 4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'),
  'chev': ('0 0 24 24', '<path d="m7 10 5 5 5-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'),
  'chevl': ('0 0 24 24', '<path d="m14 7-5 5 5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'),
  'chevr': ('0 0 24 24', '<path d="m10 7 5 5-5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'),
  'clip': ('0 0 24 24', '<path d="m20 11.5-8.2 8.2a5 5 0 0 1-7.1-7.1l8.6-8.6a3.4 3.4 0 0 1 4.8 4.8L9.6 17.3a1.7 1.7 0 0 1-2.4-2.4l7.9-7.9" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'),
  'copy': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="8" y="8" width="12" height="12" rx="2.5"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></g>'),
  'db': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8"><ellipse cx="12" cy="5.5" rx="7.5" ry="2.5"/><path d="M4.5 5.5v13c0 1.4 3.4 2.5 7.5 2.5s7.5-1.1 7.5-2.5v-13M4.5 12c0 1.4 3.4 2.5 7.5 2.5s7.5-1.1 7.5-2.5"/></g>'),
  'dl': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11M7 10l5 5 5-5M5 20h14"/></g>'),
  'dots': ('0 0 24 24', '<g fill="currentColor"><circle cx="5.5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="18.5" cy="12" r="1.7"/></g>'),
  'eye': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8"><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/></g>'),
  'file': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5z"/><path d="M14 3v5h5M9 13h6M9 17h6"/></g>'),
  'globe': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 3.7 5.6 3.7 9s-1.2 6.4-3.7 9c-2.5-2.6-3.7-5.6-3.7-9S9.5 5.6 12 3z"/></g>'),
  'grid': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3.5" y="3.5" width="7" height="7" rx="1.8"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.8"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.8"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.8"/></g>'),
  'hist': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 12a8.5 8.5 0 1 0 2.5-6L3.5 8.5"/><path d="M3.5 4v4.5H8M12 7.5V12l3 2"/></g>'),
  'info': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5h.01"/></g>'),
  'layers': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="m12 3 9 5-9 5-9-5 9-5z"/><path d="m3 13 9 5 9-5M3 17.5l9 5 9-5" opacity=".7"/></g>'),
  'line': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17l5-5 4 3 8-8"/><path d="M3 21h18"/></g>'),
  'link': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/></g>'),
  'locate': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="6.5"/><circle cx="12" cy="12" r="2" fill="currentColor"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3"/></g>'),
  'lock': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/></g>'),
  'logout': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 20.5H6a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2h3.5M15.5 16.5 20 12l-4.5-4.5M20 12H9.5"/></g>'),
  'mail': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m4 7 8 6 8-6"/></g>'),
  'map': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M9 4 3.5 6v14L9 18l6 2 5.5-2V4L15 6 9 4z"/><path d="M9 4v14M15 6v14"/></g>'),
  'max': ('0 0 24 24', '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'),
  'mic': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/></g>'),
  'minus': ('0 0 24 24', '<path d="M5 12h14" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>'),
  'monitor': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="3" y="4" width="18" height="12.5" rx="2"/><path d="M8.5 20.5h7M12 16.5v4"/></g>'),
  'moon': ('0 0 24 24', '<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>'),
  'palette': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M12 3a9 9 0 1 0 0 18c1.2 0 1.8-.9 1.5-2-.4-1.3.4-2.5 1.8-2.5H18a3 3 0 0 0 3-3C21 7 17 3 12 3z"/><circle cx="7.5" cy="11" r="1.2" fill="currentColor"/><circle cx="10.5" cy="7" r="1.2" fill="currentColor"/><circle cx="15.5" cy="7.5" r="1.2" fill="currentColor"/></g>'),
  'phone': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M11 18.5h2"/></g>'),
  'pin': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 21s-7-6.2-7-11.5a7 7 0 0 1 14 0C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/></g>'),
  'pkg': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 3 4 7v10l8 4 8-4V7l-8-4z"/><path d="M4 7l8 4 8-4M12 11v10"/></g>'),
  'plus': ('0 0 24 24', '<path d="M12 5v14M5 12h14" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>'),
  'pulse': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h4l2.5-6 5 12 2.5-6h4"/></g>'),
  'refresh': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 11a8 8 0 0 0-14.6-4.5L3.5 9M4 13a8 8 0 0 0 14.6 4.5l1.9-2.5"/><path d="M3.5 4v5h5M20.5 20v-5h-5"/></g>'),
  'search': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/></g>'),
  'send': ('0 0 24 24', '<path d="M21 3 10 14M21 3l-7 18-4-7-7-4 18-7z" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>'),
  'share': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="18" cy="5.5" r="2.5"/><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="18.5" r="2.5"/><path d="m8.2 10.8 7.6-4M8.2 13.2l7.6 4"/></g>'),
  'shield': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 3 4.5 6v5.5c0 4.5 3.2 8 7.5 9.5 4.3-1.5 7.5-5 7.5-9.5V6z"/><path d="m9 12 2 2 4-4" stroke-linecap="round"/></g>'),
  'spark': ('0 0 24 24', '<path fill="currentColor" d="M12 2.5l2.1 5.9 5.9 2.1-5.9 2.1L12 18.5l-2.1-5.9L4 10.5l5.9-2.1L12 2.5zm6.5 12l.9 2.6 2.6.9-2.6.9-.9 2.6-.9-2.6-2.6-.9 2.6-.9.9-2.6z"/>'),
  'sun': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/></g>'),
  'table': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="M3.5 9.5h17M3.5 14.5h17M10 9.5v10"/></g>'),
  'tower': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 10 8 21M12 10l4 11M9.5 16h5"/><circle cx="12" cy="8.5" r="1.5"/><path d="M8 5a6 6 0 0 0 0 7M16 5a6 6 0 0 1 0 7"/></g>'),
  'up': ('0 0 24 24', '<path d="M7 10v10H4V10h3zm3 10h7.6a2 2 0 0 0 2-1.6l1.3-6.5A2 2 0 0 0 19 9.5h-5l.8-4a1.6 1.6 0 0 0-3-1L10 10v10z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>'),
  'user': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="8" r="4"/><path d="M4 20.5a8 8 0 0 1 16 0"/></g>'),
  'users': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6.5 6.5 0 0 1 3.5 6"/></g>'),
  'wallet': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3" y="6" width="18" height="14" rx="2.5"/><path d="M3 10h18M16 15h2"/><path d="M6 6V5a2 2 0 0 1 2-2h9"/></g>'),
  'warn': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M10.3 4.2 2.6 18a2 2 0 0 0 1.7 3h15.4a2 2 0 0 0 1.7-3L13.7 4.2a2 2 0 0 0-3.4 0z"/><path d="M12 9.5v4.5M12 17.5h.01"/></g>'),
  'zoomto': ('0 0 24 24', '<g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/><circle cx="12" cy="12" r="2.5"/></g>'),
};

/// One mockup icon, tinted with [color] (the mockup draws them with currentColor).
class MIcon extends StatelessWidget {
  const MIcon(this.name, {super.key, this.size = 20, this.color});
  final String name;
  final double size;
  final Color? color;

  static bool has(String name) => _icons.containsKey(name);

  @override
  Widget build(BuildContext context) {
    final def = _icons[name];
    if (def == null) return SizedBox(width: size, height: size);
    final c = color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF0F1F1D);
    final hex = '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final op = c.a < 1 ? ' opacity="${c.a.toStringAsFixed(3)}"' : '';
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="${def.$1}" color="$hex"$op>${def.$2.replaceAll('currentColor', hex)}</svg>';
    return SvgPicture.string(svg, width: size, height: size);
  }
}
