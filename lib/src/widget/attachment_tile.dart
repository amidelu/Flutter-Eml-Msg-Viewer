import 'package:flutter/material.dart';

import '../model/mail_attachment.dart';

/// One row in the attachments list: an icon, file name, formatted size, and
/// a download affordance.
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({super.key, required this.attachment, required this.onTap});

  final MailAttachment attachment;
  final VoidCallback onTap;

  IconData get _icon {
    final mime = attachment.mimeType.toLowerCase();
    final name = attachment.fileName.toLowerCase();
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('video/')) return Icons.movie_outlined;
    if (mime.contains('pdf') || name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (name.endsWith('.doc') || name.endsWith('.docx') || name.endsWith('.xls') ||
        name.endsWith('.xlsx') || name.endsWith('.ppt') || name.endsWith('.pptx')) {
      return Icons.description_outlined;
    }
    if (name.endsWith('.eml') || name.endsWith('.msg')) return Icons.mail_outline;
    return Icons.attach_file;
  }

  String? get _formattedSize {
    final bytes = attachment.size;
    if (bytes == null || bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final size = _formattedSize;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(_icon, size: 20, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    attachment.fileName,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (size != null) ...[
                  const SizedBox(width: 12),
                  Text(size, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
                const SizedBox(width: 8),
                Icon(Icons.open_in_new, size: 18, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
