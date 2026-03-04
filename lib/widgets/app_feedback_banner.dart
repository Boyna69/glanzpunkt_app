import 'package:flutter/material.dart';

enum AppFeedbackSeverity { info, warning, error }

class AppFeedbackBanner extends StatelessWidget {
  final String message;
  final String? title;
  final AppFeedbackSeverity severity;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  const AppFeedbackBanner({
    super.key,
    required this.message,
    this.title,
    this.severity = AppFeedbackSeverity.error,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  Color _backgroundColor(BuildContext context) {
    switch (severity) {
      case AppFeedbackSeverity.info:
        return Colors.blue.shade900;
      case AppFeedbackSeverity.warning:
        return Colors.orange.shade900;
      case AppFeedbackSeverity.error:
        return Colors.red.shade900;
    }
  }

  IconData _icon() {
    switch (severity) {
      case AppFeedbackSeverity.info:
        return Icons.info_outline;
      case AppFeedbackSeverity.warning:
        return Icons.warning_amber_outlined;
      case AppFeedbackSeverity.error:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _backgroundColor(context),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(), color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null && title!.trim().isNotEmpty) ...[
                        Text(
                          title!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        message,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
              ],
            ),
            if (actionLabel != null && onAction != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
