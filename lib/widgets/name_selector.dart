import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart';

/// Pill-style name selector matching the web app's detected-names chips.
class NameSelector extends StatelessWidget {
  final List<String> names;
  final String? selectedName;
  final ValueChanged<String> onSelected;

  const NameSelector({
    super.key,
    required this.names,
    required this.selectedName,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) {
      return Text(
        'No participants detected. Please enter a name manually.',
        style: GoogleFonts.spaceGrotesk(color: kInkSoft, fontSize: 14),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Who is this portrait about?',
          style: GoogleFonts.spaceGrotesk(
            color: kInkStrong,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select the person whose personality you want to analyze.',
          style: GoogleFonts.spaceGrotesk(color: kInkMuted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        // Pill chips — horizontal wrap
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...names.map((name) => _NamePill(
                  name: name,
                  isSelected: name == selectedName,
                  onTap: () => onSelected(name),
                )),
          ],
        ),
        const SizedBox(height: 12),
        _ManualEntryRow(
          onSubmit: onSelected,
          currentSelection: selectedName,
          knownNames: names,
        ),
      ],
    );
  }
}

class _NamePill extends StatelessWidget {
  final String name;
  final bool isSelected;
  final VoidCallback onTap;

  const _NamePill({
    required this.name,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(colors: kGradientStops)
              : null,
          color: isSelected ? null : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : kBorderStrong,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: kAccentPurple.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check, color: Colors.white, size: 14),
              const SizedBox(width: 6),
            ],
            Text(
              name,
              style: GoogleFonts.spaceGrotesk(
                color: isSelected ? Colors.white : kInk,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualEntryRow extends StatefulWidget {
  final ValueChanged<String> onSubmit;
  final String? currentSelection;
  final List<String> knownNames;

  const _ManualEntryRow({
    required this.onSubmit,
    required this.currentSelection,
    required this.knownNames,
  });

  @override
  State<_ManualEntryRow> createState() => _ManualEntryRowState();
}

class _ManualEntryRowState extends State<_ManualEntryRow> {
  bool _expanded = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kSurfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorderSoft),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.edit_outlined,
                    size: 15, color: kAccentPurple),
                const SizedBox(width: 8),
                Text(
                  'Enter a different name',
                  style: GoogleFonts.spaceGrotesk(
                    color: kAccentPurple,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: kAccentPurple,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          style: GoogleFonts.spaceGrotesk(
                            color: kInkStrong,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Name',
                            hintStyle: GoogleFonts.spaceGrotesk(
                              color: kInkMuted,
                              fontSize: 14,
                            ),
                          ),
                          onSubmitted: _submit,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _GradientButton(
                        onPressed: () => _submit(_controller.text),
                        label: 'Use',
                        minWidth: 72,
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  void _submit(String value) {
    final name = value.trim();
    if (name.isNotEmpty) {
      widget.onSubmit(name);
      setState(() => _expanded = false);
      _controller.clear();
    }
  }
}

/// Reusable gradient button widget.
class _GradientButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final double minWidth;

  const _GradientButton({
    required this.onPressed,
    required this.label,
    this.minWidth = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        constraints: BoxConstraints(minWidth: minWidth, minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: kGradientStopsStrong),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: kAccentPurple.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
