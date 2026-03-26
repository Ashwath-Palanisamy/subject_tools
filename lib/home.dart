import 'package:flutter/material.dart';
import 'package:subject_tools/Helpers/appbar.dart';
import 'package:subject_tools/question_shuffler.dart';
import 'package:subject_tools/pdf_merger_page.dart';

class Home extends StatelessWidget {
  const Home({super.key});

  void _openPdfTool(BuildContext context) {
    try {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const PdfToolPage(),
        ),
      );
    } catch (e) {
      debugPrint('Error opening PDF Tool: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening PDF Tool: $e')),
        );
      }
    }
  }

  void _openPdfMerger(BuildContext context) {
    try {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const PdfMergerPage(),
        ),
      );
    } catch (e) {
      debugPrint('Error opening PDF Merger: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening PDF Merger: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDarkMode ? const Color(0xFF0F172A) : const Color(0xFF0F172A);

    return Scaffold(
      appBar: const Appbartop(),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: headerColor,
              ),
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'Subject Tools',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Tools'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF Reader'),
              onTap: () {
                Navigator.pop(context);
                _openPdfTool(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.merge),
              title: const Text('PDF Merger'),
              onTap: () {
                Navigator.pop(context);
                _openPdfMerger(context);
              },
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode
                ? const <Color>[Color(0xFF020617), Color(0xFF111827)]
                : const <Color>[Color(0xFFF8FAFC), Color(0xFFE0F2FE)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Subject Tools',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Design question papers faster: extract, review, shuffle, and merge PDFs.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ToolActionCard(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Import and Read PDF',
              subtitle: 'Extract questions, review, edit, then shuffle and export.',
              color: const Color(0xFF0EA5E9),
              onTap: () => _openPdfTool(context),
            ),
            const SizedBox(height: 12),
            _ToolActionCard(
              icon: Icons.merge,
              title: 'Merge PDFs',
              subtitle: 'Combine multiple documents into a single clean file.',
              color: const Color(0xFF059669),
              onTap: () => _openPdfMerger(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolActionCard extends StatelessWidget {
  const _ToolActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF111827) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDarkMode
                  ? const Color(0xFF374151)
                  : const Color(0xFFD1D5DB),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.22 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}