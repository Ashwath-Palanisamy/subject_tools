import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:subject_tools/main.dart' show getThemeModeNotifier;
import 'package:syncfusion_flutter_pdf/pdf.dart';

const String _footerBranding = 'Subject Tools created by Ashwath Palanisamy';

class PdfMergerPage extends StatefulWidget {
  const PdfMergerPage({super.key});

  @override
  State<PdfMergerPage> createState() => _PdfMergerPageState();
}

class _PdfMergerPageState extends State<PdfMergerPage> {
  final List<PdfFile> _selectedFiles = <PdfFile>[];
  bool _isMergingPdf = false;

  void _toggleTheme() {
    try {
      final ValueNotifier<ThemeMode> themeModeNotifier = getThemeModeNotifier();
      themeModeNotifier.value = themeModeNotifier.value == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    } catch (e) {
      debugPrint('Error toggling theme: $e');
    }
  }

  Future<void> _pickPdfFiles() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['pdf'],
        allowMultiple: true,
        withData: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final List<PdfFile> newFiles = <PdfFile>[];
      for (final PlatformFile file in result.files) {
        if (file.path != null && file.name.isNotEmpty) {
          newFiles.add(PdfFile(path: file.path!, name: file.name));
        }
      }

      setState(() {
        _selectedFiles.addAll(newFiles);
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${newFiles.length} PDF(s)')),
      );
    } catch (error) {
      debugPrint('Error picking files: $error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _reorderFiles(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final PdfFile item = _selectedFiles.removeAt(oldIndex);
    _selectedFiles.insert(newIndex, item);
    setState(() {});
  }

  void _drawFooterOnPage(
    PdfPage page,
    int pageNumber,
    int totalPages,
    PdfPen separatorPen,
    PdfFont footerFont,
  ) {
    final Size pageSize = page.getClientSize();
    final String footerText =
        '$_footerBranding  |  Page $pageNumber of $totalPages';

    page.graphics.drawLine(
      separatorPen,
      Offset(0, pageSize.height - 20),
      Offset(pageSize.width, pageSize.height - 20),
    );

    page.graphics.drawString(
      footerText,
      footerFont,
      bounds: Rect.fromLTWH(0, pageSize.height - 16, pageSize.width, 12),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
      brush: PdfBrushes.darkGray,
    );
  }

  Future<void> _mergePdfs() async {
    if (_selectedFiles.isEmpty || _selectedFiles.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 2 PDFs to merge')),
      );
      return;
    }

    setState(() {
      _isMergingPdf = true;
    });

    late PdfDocument outputDocument;

    try {
      outputDocument = PdfDocument();

      // Merge PDFs one-by-one to keep memory usage low.
      for (final PdfFile pdfFile in _selectedFiles) {
        PdfDocument? inputDocument;
        try {
          final File file = File(pdfFile.path);
          if (await file.exists()) {
            final Uint8List bytes = await file.readAsBytes();
            if (bytes.isEmpty) {
              throw Exception('${pdfFile.name} is empty');
            }
            inputDocument = PdfDocument(inputBytes: bytes);

            for (int i = 0; i < inputDocument.pages.count; i++) {
              final PdfPage page = inputDocument.pages[i];
              final PdfPage newPage = outputDocument.pages.add();
              final PdfTemplate template = page.createTemplate();
              newPage.graphics.drawPdfTemplate(
                template,
                Offset.zero,
                Size(newPage.getClientSize().width, newPage.getClientSize().height),
              );
            }
          } else {
            throw Exception('${pdfFile.name} not found');
          }
        } catch (e) {
          debugPrint('Error processing ${pdfFile.name}: $e');
          rethrow;
        } finally {
          inputDocument?.dispose();
        }
      }

      final int totalPages = outputDocument.pages.count;
      final PdfPen footerSeparatorPen = PdfPen(PdfColor(190, 190, 190), width: 0.7);
      final PdfFont footerFont = PdfStandardFont(PdfFontFamily.helvetica, 8);
      for (int i = 0; i < totalPages; i++) {
        _drawFooterOnPage(
          outputDocument.pages[i],
          i + 1,
          totalPages,
          footerSeparatorPen,
          footerFont,
        );
      }

      // Save merged PDF
      if (kIsWeb) {
        throw Exception('Saving merged PDFs is not supported in this build target.');
      }

      final Uint8List mergedBytes = Uint8List.fromList(await outputDocument.save());

      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save merged PDF',
        fileName: 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf',
        type: FileType.custom,
        allowedExtensions: <String>['pdf'],
        bytes: mergedBytes,
      );

      if (path == null || path.trim().isEmpty) {
        return;
      }

      final bool isDesktopPlatform =
          !kIsWeb &&
          (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
      if (isDesktopPlatform) {
        await File(path).writeAsBytes(
          mergedBytes,
          flush: true,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedFiles.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDFs merged successfully!')),
      );
    } catch (error, stackTrace) {
      debugPrint('PDF merge failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to merge PDFs: $error')),
      );
    } finally {
      // Cleanup resources
      outputDocument.dispose();
      
      if (mounted) {
        setState(() {
          _isMergingPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PDF Merger',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 2,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Center(
              child: Tooltip(
                message: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                child: IconButton(
                  onPressed: _toggleTheme,
                  icon: Icon(
                    isDarkMode ? Icons.light_mode : Icons.dark_mode,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ElevatedButton.icon(
              onPressed: _isMergingPdf ? null : _pickPdfFiles,
              icon: const Icon(Icons.upload_file, size: 22),
              label: const Text(
                'Select PDFs',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
            const SizedBox(height: 16),

            // Info box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50.withValues(alpha: isDarkMode ? 0.15 : 0.5),
                border: Border.all(
                  color: Colors.amber.shade400.withValues(alpha: isDarkMode ? 0.6 : 1),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Selected: ${_selectedFiles.length} PDF(s). Drag to reorder. Minimum 2 PDFs required.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.amber.shade900.withValues(alpha: isDarkMode ? 0.9 : 1),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Files list
            Expanded(
              child: _selectedFiles.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey.shade900 : Colors.grey.shade50,
                        border: Border.all(
                          color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'No PDFs selected\nTap "Select PDFs" to choose files',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ReorderableListView(
                      onReorder: _reorderFiles,
                      children: <Widget>[
                        for (int index = 0; index < _selectedFiles.length; index++)
                          Card(
                            key: Key('file_$index'),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle),
                              ),
                              title: Text(_selectedFiles[index].name),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _removeFile(index),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),

            const SizedBox(height: 12),

            // Merge button
            ElevatedButton.icon(
              onPressed: _isMergingPdf ? null : _mergePdfs,
              icon: _isMergingPdf
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    )
                  : const Icon(Icons.merge, size: 22),
              label: Text(
                _isMergingPdf ? 'Merging...' : 'Merge PDFs',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PdfFile {
  final String path;
  final String name;

  PdfFile({required this.path, required this.name});
}
