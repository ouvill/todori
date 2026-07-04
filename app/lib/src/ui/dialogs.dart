import 'package:flutter/material.dart';
import 'package:todori/src/ui/theme.dart';

Future<String?> showAppTextInputDialog({
  required BuildContext context,
  required String title,
  required String label,
  required String cancelLabel,
  required String submitLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _AppTextInputDialog(
      title: title,
      label: label,
      cancelLabel: cancelLabel,
      submitLabel: submitLabel,
    ),
  );
}

Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        _DialogActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ],
      actionsPadding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
    ),
  );
  return confirmed ?? false;
}

class _AppTextInputDialog extends StatefulWidget {
  const _AppTextInputDialog({
    required this.title,
    required this.label,
    required this.cancelLabel,
    required this.submitLabel,
  });

  final String title;
  final String label;
  final String cancelLabel;
  final String submitLabel;

  @override
  State<_AppTextInputDialog> createState() => _AppTextInputDialogState();
}

class _AppTextInputDialogState extends State<_AppTextInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        _DialogActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(widget.cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_controller.text),
              child: Text(widget.submitLabel),
            ),
          ],
        ),
      ],
      actionsPadding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: children,
    );
  }
}
