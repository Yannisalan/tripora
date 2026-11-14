import 'package:flutter/material.dart';

import '../../core/design/glass/glass_background.dart';
import '../../core/design/glass/glass_tokens.dart';
import '../../core/theme/app_theme.dart';
import 'legal_content.dart';

/// Renders a legal document (Terms / Privacy Policy) as a scrollable,
/// theme-aware list of sections.
class LegalScreen extends StatelessWidget {
  const LegalScreen({
    super.key,
    required this.title,
    required this.sections,
  });

  final String title;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.triporaColors;

    return GlassBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
          ),
        ),
      ),
      // Legal text keeps a readable line length on wide windows.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final gutter = TriporaBreakpoints.gutterFor(
            constraints.maxWidth,
            maxContentWidth: 760,
            minGutter: 24,
          );
          return ListView(
        padding: EdgeInsets.fromLTRB(
          gutter,
          12,
          gutter,
          40 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          for (final section in sections) ...[
            if (section.title.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                section.title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            for (final paragraph in section.body.split('\n\n'))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _resolvePlaceholders(paragraph),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 15,
                    height: 1.5,
                    color: colors.textSecondary,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
        ],
      );
        },
      ),
      ),
    );
  }

  String _resolvePlaceholders(String text) {
    return text.replaceAll('{{LEGAL_CONTACT_EMAIL}}', 'gotripora@gmail.com');
  }
}
