import 'package:flutter/material.dart';

/// A selectable list of participant names extracted from the chat.
///
/// The user taps a name to designate it as the portrait subject.
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
    final theme = Theme.of(context);

    if (names.isEmpty) {
      return Text(
        'No participants detected. Please enter a name manually.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Who is this portrait about?',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select the person whose personality you want to analyze.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ...names.map((name) => _NameTile(
              name: name,
              isSelected: name == selectedName,
              onTap: () => onSelected(name),
            )),
        const SizedBox(height: 8),
        _ManualEntryTile(
          onSubmit: onSelected,
          currentSelection: selectedName,
          knownNames: names,
        ),
      ],
    );
  }
}

class _NameTile extends StatelessWidget {
  final String name;
  final bool isSelected;
  final VoidCallback onTap;

  const _NameTile({
    required this.name,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? primary
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: isSelected
                  ? primary
                  : Colors.white.withValues(alpha: 0.12),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: primary, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Allows the user to type a name that wasn't detected automatically.
class _ManualEntryTile extends StatefulWidget {
  final ValueChanged<String> onSubmit;
  final String? currentSelection;
  final List<String> knownNames;

  const _ManualEntryTile({
    required this.onSubmit,
    required this.currentSelection,
    required this.knownNames,
  });

  @override
  State<_ManualEntryTile> createState() => _ManualEntryTileState();
}

class _ManualEntryTileState extends State<_ManualEntryTile> {
  bool _expanded = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Show "other name" tile only when no known name is selected or always.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: Colors.white54,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Enter a different name',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white54),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.white54,
                  size: 18,
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
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            hintText: 'Name',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          onSubmitted: _submit,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(72, 52),
                        ),
                        onPressed: () => _submit(_controller.text),
                        child: const Text('Use'),
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
    }
  }
}
