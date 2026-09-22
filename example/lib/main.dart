import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_eml_msg_viewer/flutter_eml_msg_viewer.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Eml Msg Viewer Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

/// Landing page: pick which of the two ways to feed [MailMessageViewer] a
/// message you want to try — local bytes (e.g. a file the user picked) or a
/// URL (e.g. a signed blob-storage link) it fetches itself.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_eml_msg_viewer example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EntryCard(
            icon: Icons.folder_open,
            title: 'From a local file',
            subtitle: 'Pick a .eml or .msg file from this device and preview it via '
                'MailMessageViewer(bytes: ...)',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LocalFilePage()),
            ),
          ),
          const SizedBox(height: 12),
          _EntryCard(
            icon: Icons.link,
            title: 'From a URL',
            subtitle: 'Fetch a .eml or .msg file over HTTP(S) and preview it via '
                'MailMessageViewer.url(url: ...)',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UrlPage()),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Demonstrates `MailMessageViewer(bytes: ...)` — the widget's default
/// constructor, for when you already have the message's raw bytes (picked
/// from disk, extracted from a zip, read from a database, etc).
class LocalFilePage extends StatefulWidget {
  const LocalFilePage({super.key});

  @override
  State<LocalFilePage> createState() => _LocalFilePageState();
}

class _LocalFilePageState extends State<LocalFilePage> {
  Uint8List? _bytes;
  String? _fileName;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['eml', 'msg'],
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    setState(() {
      _bytes = file!.bytes;
      _fileName = file.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      appBar: AppBar(title: Text(_fileName ?? 'From a local file')),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickFile,
        tooltip: 'Pick a .eml or .msg file',
        child: const Icon(Icons.folder_open),
      ),
      body: bytes == null
          ? const Center(child: Text('Pick a .eml or .msg file to preview it'))
          : MailMessageViewer(bytes: bytes),
    );
  }
}

/// Demonstrates `MailMessageViewer.url(...)` — for when the message lives
/// somewhere over HTTP(S) (e.g. a signed blob-storage URL from your own
/// backend) and you'd rather the widget fetch and parse it itself than do
/// that yourself first.
class UrlPage extends StatefulWidget {
  const UrlPage({super.key});

  @override
  State<UrlPage> createState() => _UrlPageState();
}

class _UrlPageState extends State<UrlPage> {
  final _controller = TextEditingController();
  String? _loadedUrl;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _load() {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    setState(() => _loadedUrl = url);
  }

  @override
  Widget build(BuildContext context) {
    final url = _loadedUrl;
    return Scaffold(
      appBar: AppBar(title: const Text('From a URL')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'https://example.com/message.eml',
                      labelText: '.eml or .msg URL',
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _load, child: const Text('Load')),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: url == null
                ? const Center(child: Text('Enter a URL above and tap Load'))
                // Headers can be passed too, e.g. for a URL that needs an
                // Authorization header: MailMessageViewer.url(url: url,
                // headers: {'Authorization': 'Bearer ...'})
                : MailMessageViewer.url(url: url),
          ),
        ],
      ),
    );
  }
}
