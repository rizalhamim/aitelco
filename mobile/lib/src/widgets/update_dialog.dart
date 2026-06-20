import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme.dart';

/// Shows the "update available" dialog. Handles download progress + install.
/// Pass [info] from UpdateService.check().
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: !info.mandatory,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  String get _sizeLabel {
    final mb = widget.info.sizeBytes / (1024 * 1024);
    return mb > 0 ? '${mb.toStringAsFixed(1)} MB' : '';
  }

  Future<void> _startUpdate() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    final err = await UpdateService.downloadAndInstall(
      widget.info,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _downloading = false;
        _error = err;
      });
    } else {
      // Installer launched — close the dialog.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.system_update, color: IOH.teal),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Update Tersedia',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Versi baru ${info.versionName} tersedia${_sizeLabel.isNotEmpty ? ' ($_sizeLabel)' : ''}.',
            style: const TextStyle(fontFamily: 'Prompt', fontSize: 14),
          ),
          if (info.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(info.notes,
                style: const TextStyle(fontFamily: 'Prompt', fontSize: 13, color: Colors.black54)),
          ],
          if (_downloading) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 8,
                backgroundColor: Colors.black12,
                valueColor: const AlwaysStoppedAnimation(IOH.teal),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _progress > 0
                  ? 'Mengunduh ${(_progress * 100).toStringAsFixed(0)}%'
                  : 'Menyiapkan unduhan…',
              style: const TextStyle(fontFamily: 'Prompt', fontSize: 12, color: Colors.black54),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                style: const TextStyle(fontFamily: 'Prompt', fontSize: 12.5, color: IOH.red)),
          ],
        ],
      ),
      actions: _downloading
          ? const [SizedBox.shrink()]
          : [
              if (!info.mandatory)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Nanti', style: TextStyle(fontFamily: 'Prompt')),
                ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: IOH.red),
                onPressed: _startUpdate,
                child: Text(_error != null ? 'Coba Lagi' : 'Update Sekarang',
                    style: const TextStyle(fontFamily: 'Prompt', fontWeight: FontWeight.w600)),
              ),
            ],
    );
  }
}
