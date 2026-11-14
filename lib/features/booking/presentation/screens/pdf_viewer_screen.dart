import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';

/// Opens a PDF already written to [filePath] (invoice, receipt...) inside the app, with Download (save to the
/// phone) and Share in the app bar.
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.filePath, required this.title, this.shareSubject});

  final String filePath;
  final String title;
  final String? shareSubject;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PdfControllerPinch? _controller;
  int _pages = 0;
  int _page = 1;
  String? _error;

  String get _fileName => '${widget.title.replaceAll(RegExp(r'[^A-Za-z0-9\-_]+'), '_')}.pdf';

  @override
  void initState() {
    super.initState();
    if (File(widget.filePath).existsSync()) {
      _controller = PdfControllerPinch(document: PdfDocument.openFile(widget.filePath));
    } else {
      _error = 'The file is no longer available.';
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    await Share.shareXFiles(
      [XFile(widget.filePath, mimeType: 'application/pdf')],
      subject: widget.shareSubject ?? widget.title,
    );
  }

  /// Saves a copy where the customer chooses (Downloads, Drive, ...).
  Future<void> _download() async {
    try {
      if (await File(widget.filePath).length() == 0) {
        if (mounted) AppToast.show(context, 'This document is empty, so it cannot be saved.', type: AppToastType.error);
        return;
      }
      final saved = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(sourceFilePath: widget.filePath, fileName: _fileName),
      );
      if (!mounted) return;
      if (saved != null) AppToast.show(context, 'Saved to your phone.', type: AppToastType.success);
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not save the file. Try Share instead.', type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed = _error != null;
    return Scaffold(
      backgroundColor: AppColors.swatchF6F8FA,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download_rounded),
            onPressed: _download,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _share,
          ),
        ],
      ),
      body: failed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined, size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    const Text('We could not display this document here.', textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    FilledButton.icon(onPressed: _download, icon: const Icon(Icons.download_rounded), label: const Text('Download')),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(onPressed: _share, icon: const Icon(Icons.ios_share_rounded), label: const Text('Share')),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                PdfViewPinch(
                  controller: _controller!,
                  backgroundDecoration: const BoxDecoration(color: AppColors.swatchF6F8FA),
                  onDocumentLoaded: (doc) => setState(() => _pages = doc.pagesCount),
                  onPageChanged: (page) => setState(() => _page = page),
                  onDocumentError: (e) => setState(() => _error = e.toString()),
                ),
                if (_pages > 1)
                  Positioned(
                    right: 12,
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                      child: Text('$_page / $_pages', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
              ],
            ),
    );
  }
}
