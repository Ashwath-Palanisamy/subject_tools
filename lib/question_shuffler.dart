import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:subject_tools/main.dart' show getThemeModeNotifier;
import 'package:syncfusion_flutter_pdf/pdf.dart';

const int _maxPdfBytes = 25 * 1024 * 1024;
const int _maxPreviewChars = 50000;
const int _pageChunkSize = 4;

final RegExp _spaceTabRunPattern = RegExp(r'[\t ]+');
final RegExp _whitespaceRunPattern = RegExp(r'\s+');
final RegExp _blankLineSplitPattern = RegExp(r'\n\s*\n');
final RegExp _urlStartPattern = RegExp(
  r'^(?:https?://|www\.)',
  caseSensitive: false,
);
final RegExp _nonAlphaNumericOnlyPattern = RegExp(
  r'^[^A-Za-z0-9\u00C0-\u024F\u1E00-\u1EFF]+$',
);
final RegExp _letterLikePattern = RegExp(r'[A-Za-z\u00C0-\u024F\u1E00-\u1EFF]');
final RegExp _digitLikePattern = RegExp(
  r'[0-9\u0660-\u0669\u06F0-\u06F9\u2080-\u2089\u2070-\u2079]',
);
final RegExp _forcedSplitQuestionPattern = RegExp(
  r'([^\n])\s+((?:Q(?:uestion)?\s*)?\d{1,3}\s*[\).:\-]\s*)',
  caseSensitive: false,
);

// Upgraded regex: handles Q1, Question 1, 1), 1., 1:, 1-, I., I), I:, I-, Q.1, Q-1, Q:1, etc.
final RegExp _questionStartPattern = RegExp(
  r'^\s*(?:'
  r'(?:Q(?:uestion)?[\s\-:\.]*)?\d{1,3}' // Q1, Question 1, Q-1, Q:1, Q.1
  r'|[IVXLCDM]{1,8}' // Roman numerals
  r')\s*[\).:\-]',
  multiLine: true,
  caseSensitive: false,
);

final RegExp _embeddedMarkTagPattern = RegExp(
  r'(?:(?:[\[(\{]\s*(?:\d{1,2}|[ivxlcdm]{1,5})\s*(?:marks?|mk|pts?|points?)\s*[\])\}])|(?:\b(?:\d{1,2}|[ivxlcdm]{1,5})\s*(?:marks?|mk|pts?|points?)\b))',
  caseSensitive: false,
);

// Upgraded: handles Q1, Q-1, Q:1, Q.1, 1), 1., 1:, 1-, I., I), I:, I-, etc.
final RegExp _leadNumberPattern = RegExp(
  r'^(?:'
  r'(?:Q(?:uestion)?[\s\-:\.]*)?\d{1,3}'
  r'|[IVXLCDM]{1,8}'
  r')\s*[\).:\-]\s*',
  caseSensitive: false,
);

final RegExp _optionPattern = RegExp(
  r'^\s*(?:\(?\s*([a-h])\s*\)?|(\d{1,2})|([ivx]{1,4}))\s*[\).:\-]\s*(.+)$',
  caseSensitive: false,
);

String _prepareTextForQuestionParsing(String input) {
  String text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAll(_spaceTabRunPattern, ' ');

  // If OCR merges "... 2. ... 3. ..." into one line, force a split.
  text = text.replaceAllMapped(
    _forcedSplitQuestionPattern,
    (Match match) => '${match.group(1)}\n${match.group(2)}',
  );

  return text;
}

bool _isLikelyGarbageLine(String line) {
  final String trimmed = line.trim();
  if (trimmed.isEmpty) {
    return true;
  }
  if (_urlStartPattern.hasMatch(trimmed)) {
    return true;
  }
  if (_nonAlphaNumericOnlyPattern.hasMatch(trimmed) && trimmed.length >= 3) {
    return true;
  }
  final int letters = _letterLikePattern.allMatches(trimmed).length;
  final int digits = _digitLikePattern.allMatches(trimmed).length;
  if (letters == 0 && digits <= 1) {
    return true;
  }
  return false;
}

List<String> _splitQuestionBlocks(String sourceText) {
  final Iterable<RegExpMatch> matches = _questionStartPattern.allMatches(
    sourceText,
  );

  if (matches.isEmpty) {
    return sourceText
        .split(_blankLineSplitPattern)
        .map((String block) => block.trim())
        .where((String block) => block.isNotEmpty)
        .toList();
  }

  final List<int> starts = matches
      .map((RegExpMatch match) => match.start)
      .toList();
  final List<String> blocks = <String>[];

  for (int index = 0; index < starts.length; index++) {
    final int start = starts[index];
    final int end = index + 1 < starts.length
        ? starts[index + 1]
        : sourceText.length;
    final String block = sourceText.substring(start, end).trim();
    if (block.isNotEmpty) {
      blocks.add(block);
    }
  }

  return blocks;
}

String _normalizeQuestionText(String input) {
  final String normalizedNewlines = input
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final List<String> rawLines = normalizedNewlines
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList();

  if (rawLines.isEmpty) {
    return '';
  }

  final List<String> stemParts = <String>[];
  final List<String> optionLines = <String>[];

  for (int i = 0; i < rawLines.length; i++) {
    String line = rawLines[i].replaceAll(_whitespaceRunPattern, ' ').trim();
    if (line.isEmpty || _isLikelyGarbageLine(line)) {
      continue;
    }

    if (i == 0) {
      line = line.replaceFirst(_leadNumberPattern, '');
    }

    line = line.replaceAll(_embeddedMarkTagPattern, '').trim();
    if (line.isEmpty) {
      continue;
    }

    final RegExpMatch? optionMatch = _optionPattern.firstMatch(line);
    if (optionMatch != null) {
      final String optionLabel =
          optionMatch.group(1)?.toLowerCase() ??
          optionMatch.group(2) ??
          optionMatch.group(3)!.toLowerCase();
      final String optionText = optionMatch.group(4)!.trim();
      if (optionText.isNotEmpty) {
        optionLines.add('$optionLabel) $optionText');
      }
      continue;
    }

    stemParts.add(line);
  }

  final String stem = stemParts
      .join(' ')
      .replaceAll(_whitespaceRunPattern, ' ')
      .trim();

  if (stem.isEmpty && optionLines.isEmpty) {
    return '';
  }

  if (optionLines.isEmpty) {
    return stem;
  }

  return '$stem\n${optionLines.join('\n')}';
}

List<String> _extractQuestions(String sourceText) {
  final String preparedText = _prepareTextForQuestionParsing(sourceText);
  final List<String> questions = <String>[];

  for (final String block in _splitQuestionBlocks(preparedText)) {
    final String cleaned = _normalizeQuestionText(block);
    if (cleaned.isNotEmpty) {
      questions.add(cleaned);
    }
  }

  return questions;
}

Future<Map<String, Object>> _extractPdfPreviewInIsolate(
  Map<String, Object> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;
  final int maxChars = args['maxChars'] as int;
  final int pageChunkSize = args['pageChunkSize'] as int;

  final PdfDocument document = PdfDocument(inputBytes: bytes);

  try {
    final PdfTextExtractor extractor = PdfTextExtractor(document);
    final int pageCount = document.pages.count;
    final StringBuffer buffer = StringBuffer();
    bool truncated = false;

    for (int start = 0; start < pageCount; start += pageChunkSize) {
      final int end = math.min(start + pageChunkSize - 1, pageCount - 1);
      final String chunk = extractor.extractText(
        startPageIndex: start,
        endPageIndex: end,
      );

      if (chunk.isEmpty) {
        continue;
      }

      final int remaining = maxChars - buffer.length;
      if (remaining <= 0) {
        truncated = true;
        break;
      }

      if (chunk.length > remaining) {
        buffer.write(chunk.substring(0, remaining));
        truncated = true;
        break;
      }

      buffer.write(chunk);
    }

    return <String, Object>{
      'text': buffer.toString(),
      'pageCount': pageCount,
      'truncated': truncated,
    };
  } finally {
    document.dispose();
  }
}

class PdfToolPage extends StatefulWidget {
  const PdfToolPage({super.key});

  @override
  State<PdfToolPage> createState() => _PdfToolPageState();
}

class _PdfToolPageState extends State<PdfToolPage> {
  bool _isReadingPdf = false;
  bool _isGeneratingPaper = false;
  bool _hasGeneratedPaper = false;
  String? _fileName;
  String _questionSummary = '';
  String? _questionCountError;
  List<String> _extractedQuestions = <String>[];
  final TextEditingController _questionCountController =
      TextEditingController();
  final TextEditingController _previewEditorController =
      TextEditingController();

  @override
  void dispose() {
    _questionCountController.dispose();
    _previewEditorController.dispose();
    super.dispose();
  }

  String _buildQuestionSummary(List<String> questions) {
    return 'Detected questions: ${questions.length}';
  }

  void _reloadPreview() {
    if (_extractedQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No questions available to reload.')),
      );
      return;
    }
    _syncPreviewWithQuestionCount();
    setState(() {
      _hasGeneratedPaper = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preview reloaded for current question count.'),
      ),
    );
  }

  void _setPresetQuestionCount(String preset, int availableQuestions) {
    int count = availableQuestions;
    if (preset == 'half') {
      count = (availableQuestions / 2).ceil();
    } else if (preset == 'quarter') {
      count = (availableQuestions / 4).ceil();
    }
    _questionCountController.text = count.toString();
    _validateQuestionCount(availableQuestions);
    _syncPreviewWithQuestionCount();
  }

  String _buildFormattedPreview(List<String> questions) {
    final StringBuffer preview = StringBuffer();
    preview.writeln('Generated Question Paper');
    preview.writeln('========================');
    preview.writeln('Total Questions: ${questions.length}');
    preview.writeln();

    for (int index = 0; index < questions.length; index++) {
      preview.writeln('${index + 1}. ${questions[index]}');
      preview.writeln();
    }

    return preview.toString();
  }

  String _buildEditableQuestionsText(List<String> questions) {
    return questions.join('\n\n');
  }

  int _resolvePreviewQuestionCount(int availableQuestions) {
    final String raw = _questionCountController.text.trim();
    final int? parsed = int.tryParse(raw);
    if (raw.isEmpty || parsed == null || parsed <= 0) {
      return availableQuestions;
    }
    return parsed.clamp(1, availableQuestions);
  }

  void _syncPreviewWithQuestionCount() {
    if (_extractedQuestions.isEmpty) {
      return;
    }

    final int previewCount = _resolvePreviewQuestionCount(
      _extractedQuestions.length,
    );
    _previewEditorController.text = _buildEditableQuestionsText(
      _extractedQuestions.take(previewCount).toList(),
    );
  }

  void _validateQuestionCount(int availableQuestions) {
    final String raw = _questionCountController.text.trim();
    if (raw.isEmpty) {
      setState(() => _questionCountError = null);
      return;
    }

    final int? parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      setState(() => _questionCountError = 'Must be a positive number');
      return;
    }
    if (parsed > availableQuestions) {
      setState(
        () => _questionCountError = 'Max: $availableQuestions available',
      );
      return;
    }
    setState(() => _questionCountError = null);
  }

  int _resolveOutputQuestionCount(int availableQuestions) {
    final String raw = _questionCountController.text.trim();
    if (raw.isEmpty) {
      return availableQuestions;
    }

    final int? parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      throw Exception('Enter a valid positive number for output questions.');
    }
    if (parsed > availableQuestions) {
      throw Exception(
        'Requested $parsed questions, but only $availableQuestions are available.',
      );
    }
    return parsed;
  }

  Future<List<int>> _getPdfBytes(PlatformFile selectedFile) async {
    if (selectedFile.bytes != null && selectedFile.bytes!.isNotEmpty) {
      return selectedFile.bytes!;
    }

    if (!kIsWeb && selectedFile.path != null) {
      final File file = File(selectedFile.path!);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    }

    throw Exception('Could not access selected PDF bytes or path.');
  }

  Future<void> _importAndReadPdf() async {
    setState(() {
      _isReadingPdf = true;
    });

    try {
      final Stopwatch stopwatch = Stopwatch()..start();

      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['pdf'],
        withData: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final PlatformFile selectedFile = result.files.single;
      final List<int> bytes = await _getPdfBytes(selectedFile);
      if (bytes.isEmpty) {
        throw Exception('Selected file is empty.');
      }

      if (bytes.length > _maxPdfBytes) {
        throw Exception('PDF is too large. Please choose a file under 25 MB.');
      }

      final Map<String, Object> extraction =
          await compute(_extractPdfPreviewInIsolate, <String, Object>{
            'bytes': Uint8List.fromList(bytes),
            'maxChars': _maxPreviewChars,
            'pageChunkSize': _pageChunkSize,
          });

      final String extractedText = extraction['text'] as String;
      final String preparedText = _prepareTextForQuestionParsing(extractedText);
      final List<String> extractedQuestions = _extractQuestions(preparedText);
      final List<String> randomizedQuestions = List<String>.from(
        extractedQuestions,
      )..shuffle(math.Random());
      final bool truncated = extraction['truncated'] as bool;

      stopwatch.stop();

      final String processedText = preparedText.trim().isEmpty
          ? 'No readable text found in this PDF.'
          : preparedText;

      final String timing =
          '\n\nProcessed ${bytes.length ~/ 1024} KB in ${stopwatch.elapsedMilliseconds} ms.';
      final String suffix = truncated
          ? '\n\nPreview truncated to the first $_maxPreviewChars characters for stability.'
          : '';
      final String extractionPreview = randomizedQuestions.isEmpty
          ? 'Extraction Preview\n==================\n$processedText$suffix$timing'
          : _buildEditableQuestionsText(randomizedQuestions);

      setState(() {
        _fileName = selectedFile.name;
        _extractedQuestions = randomizedQuestions;
        _questionSummary = _buildQuestionSummary(randomizedQuestions);
        _previewEditorController.text = extractionPreview;
      });

      if (randomizedQuestions.isNotEmpty) {
        _validateQuestionCount(randomizedQuestions.length);
        _syncPreviewWithQuestionCount();
      }
    } catch (error, stackTrace) {
      debugPrint('PDF import/read failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to import or read the PDF: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isReadingPdf = false;
        });
      }
    }
  }

  Future<void> _shuffleQuestions() async {
    if (_extractedQuestions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Import a PDF first.')));
      return;
    }

    setState(() {
      _isGeneratingPaper = true;
    });

    try {
      final math.Random random = math.Random();
      final List<String> shuffledQuestions = List<String>.from(
        _extractedQuestions,
      );
      shuffledQuestions.shuffle(random);
      final int outputCount = _resolveOutputQuestionCount(
        _extractedQuestions.length,
      );
      final List<String> selectedQuestions = shuffledQuestions
          .take(outputCount)
          .toList();

      final String formattedPreview = _buildFormattedPreview(selectedQuestions);

      if (!mounted) {
        return;
      }

      setState(() {
        _previewEditorController.text = formattedPreview;
        _isGeneratingPaper = false;
        _hasGeneratedPaper = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Questions shuffled successfully.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Question shuffling failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }

      setState(() {
        _isGeneratingPaper = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    }
  }

  Future<void> _exportAsPdf() async {
    final String content = _previewEditorController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shuffle questions first before exporting.'),
        ),
      );
      return;
    }

    setState(() {
      _isGeneratingPaper = true;
    });

    try {
      final PdfDocument document = PdfDocument();
      final PdfPage page = document.pages.add();

      final PdfFont titleFont = PdfStandardFont(
        PdfFontFamily.helvetica,
        16,
        style: PdfFontStyle.bold,
      );
      final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);

      // Draw title
      page.graphics.drawString(
        'Question Paper',
        titleFont,
        bounds: Rect.fromLTWH(0, 0, page.getClientSize().width, 24),
      );

      // Draw content
      final PdfTextElement element = PdfTextElement(
        text: content,
        font: bodyFont,
      );
      element.draw(
        page: page,
        bounds: Rect.fromLTWH(
          0,
          30,
          page.getClientSize().width,
          page.getClientSize().height - 30,
        ),
        format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
      );

      // Add footer to all pages
      final PdfFont footerFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
      final int totalPages = document.pages.count;
      for (int i = 0; i < totalPages; i++) {
        final PdfPage footerPage = document.pages[i];
        final double pageHeight = footerPage.getClientSize().height;
        final double pageWidth = footerPage.getClientSize().width;
        final String footerText =
            'Page ${i + 1} of $totalPages — Created by subject created by Ashwath';
        footerPage.graphics.drawString(
          footerText,
          footerFont,
          bounds: Rect.fromLTWH(0, pageHeight - 20, pageWidth, 15),
        );
      }

      final List<int> bytes = await document.save();
      document.dispose();

      if (kIsWeb) {
        throw Exception('Saving PDFs is not supported in this build target.');
      }

      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save question paper',
        fileName: 'question_paper_${DateTime.now().millisecondsSinceEpoch}.pdf',
        type: FileType.custom,
        allowedExtensions: <String>['pdf'],
        bytes: Uint8List.fromList(bytes),
      );

      if (path == null || path.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _isGeneratingPaper = false;
        });
        return;
      }

      final bool isDesktopPlatform =
          !kIsWeb &&
          (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
      if (isDesktopPlatform) {
        await File(path).writeAsBytes(Uint8List.fromList(bytes), flush: true);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isGeneratingPaper = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question paper exported successfully.')),
      );
    } catch (error, stackTrace) {
      debugPrint('PDF export failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) {
        return;
      }

      setState(() {
        _isGeneratingPaper = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  void _toggleTheme() {
    final ValueNotifier<ThemeMode> themeModeNotifier = getThemeModeNotifier();
    themeModeNotifier.value = themeModeNotifier.value == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final int readyToShuffleCount = _extractedQuestions.length;
    final int showingPreviewCount = readyToShuffleCount == 0
        ? 0
        : _resolvePreviewQuestionCount(readyToShuffleCount);
    final Color panelColor = isDarkMode
        ? const Color(0xFF111827)
        : const Color(0xFFFAFAFF);
    final Color panelBorder = isDarkMode
        ? const Color(0xFF374151)
        : const Color(0xFFD1D5DB);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PDF Question Shuffler',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
        elevation: 0,
        backgroundColor: isDarkMode
            ? const Color(0xFF0B1220)
            : const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Tooltip(
                message: isDarkMode
                    ? 'Switch to Light Mode'
                    : 'Switch to Dark Mode',
                child: IconButton(
                  onPressed: _toggleTheme,
                  icon: Icon(
                    isDarkMode ? Icons.light_mode : Icons.dark_mode,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode
                ? const <Color>[Color(0xFF020617), Color(0xFF0F172A)]
                : const <Color>[Color(0xFFF8FAFC), Color(0xFFE0F2FE)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget controlPanel = Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panelColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: panelBorder),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.tune_rounded),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Easy steps: 1) Pick PDF  2) Choose number  3) Make paper  4) Save',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Just Do This',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'If you are not sure, leave the number box empty. It will use all questions.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          Chip(
                            avatar: const Icon(Icons.topic, size: 16),
                            label: Text(
                              _questionSummary.isEmpty
                                  ? 'Detected questions: 0'
                                  : _questionSummary,
                            ),
                          ),
                          Chip(
                            avatar: const Icon(Icons.edit_note, size: 16),
                            label: Text(
                              'Ready to shuffle: $readyToShuffleCount',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _isReadingPdf ? null : _importAndReadPdf,
                        icon: _isReadingPdf
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_rounded),
                        label: Text(
                          _isReadingPdf ? 'Reading PDF...' : '1. Pick PDF File',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0EA5E9),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      if (_fileName != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.description_outlined),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _fileName!,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _questionCountController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) {
                          _validateQuestionCount(readyToShuffleCount);
                          _syncPreviewWithQuestionCount();
                        },
                        decoration: InputDecoration(
                          labelText: 'How many questions do you want?',
                          hintText: 'Example: 10 (or leave empty for all)',
                          helperText: _questionCountError == null
                              ? 'Available: $readyToShuffleCount'
                              : null,
                          errorText: _questionCountError,
                          prefixIcon: const Icon(Icons.format_list_numbered),
                          filled: true,
                          fillColor: isDarkMode
                              ? const Color(0xFF020617)
                              : Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: <Widget>[
                          FilledButton.tonal(
                            onPressed: readyToShuffleCount > 0
                                ? () => _setPresetQuestionCount(
                                    'all',
                                    readyToShuffleCount,
                                  )
                                : null,
                            child: const Text('Use All'),
                          ),
                          FilledButton.tonal(
                            onPressed: readyToShuffleCount > 0
                                ? () => _setPresetQuestionCount(
                                    'half',
                                    readyToShuffleCount,
                                  )
                                : null,
                            child: const Text('Use Half'),
                          ),
                          FilledButton.tonal(
                            onPressed: readyToShuffleCount > 0
                                ? () => _setPresetQuestionCount(
                                    'quarter',
                                    readyToShuffleCount,
                                  )
                                : null,
                            child: const Text('Use Few'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (readyToShuffleCount > 0)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  'Preview (you can edit text)',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Row(
                                  children: <Widget>[
                                    Text(
                                      'Showing: $showingPreviewCount/$readyToShuffleCount',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF059669),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      height: 28,
                                      child: OutlinedButton.icon(
                                        onPressed: _reloadPreview,
                                        icon: const Icon(
                                          Icons.refresh,
                                          size: 16,
                                        ),
                                        label: const Text('Reset'),
                                        style: ButtonStyle(
                                          padding: WidgetStateProperty.all(
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? const Color(0xFF020617)
                                    : Colors.white,
                                border: Border.all(
                                  color: isDarkMode
                                      ? const Color(0xFF374151)
                                      : const Color(0xFFD1D5DB),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextField(
                                controller: _previewEditorController,
                                maxLines: null,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.all(10),
                                  border: InputBorder.none,
                                  hintText:
                                      'Your questions will appear here...',
                                  hintStyle: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: isDarkMode
                                            ? Colors.grey[600]
                                            : Colors.grey[400],
                                      ),
                                ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontFamily: 'monospace'),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ElevatedButton.icon(
                        onPressed: (_isReadingPdf || _isGeneratingPaper)
                            ? null
                            : _shuffleQuestions,
                        icon: _isGeneratingPaper
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.shuffle_rounded),
                        label: Text(
                          _isGeneratingPaper
                              ? 'Making Question Paper...'
                              : '2. Make Question Paper',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed:
                            (_previewEditorController.text.isEmpty ||
                                !_hasGeneratedPaper)
                            ? null
                            : _exportAsPdf,
                        icon: const Icon(Icons.file_download_rounded),
                        label: const Text('3. Save as PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF3F2E00)
                              : const Color(0xFFFFF7D6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Tip: You can change any text in preview before saving.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              );

              return Padding(
                padding: const EdgeInsets.all(14),
                child: controlPanel,
              );
            },
          ),
        ),
      ),
    );
  }
}
