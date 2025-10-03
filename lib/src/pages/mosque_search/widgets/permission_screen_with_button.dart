import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:mawaqit/i18n/l10n.dart';
import 'package:mawaqit/src/pages/onBoarding/widgets/on_boarding_permission_adhan_screen.dart';

/// A wrapper widget that displays the permission screen with a styled "Ok" button
/// Used when accessing mosque search from settings (not during onboarding)
class PermissionScreenWithButton extends StatefulWidget {
  final Option<FocusNode> selectedNode;

  const PermissionScreenWithButton({
    super.key,
    required this.selectedNode,
  });

  @override
  State<PermissionScreenWithButton> createState() => _PermissionScreenWithButtonState();
}

class _PermissionScreenWithButtonState extends State<PermissionScreenWithButton> {
  bool _isSaving = false;

  Future<void> _handleDone() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Schedule notifications if user enabled them
      await OnBoardingPermissionAdhanScreen.scheduleIfEnabled(context);

      // Close the screen
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: OnBoardingPermissionAdhanScreen(
                isOnboarding: false,
                nextButtonFocusNode: widget.selectedNode,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: _isSaving ? null : _handleDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: theme.primaryColor.withOpacity(0.6),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        S.of(context).ok,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
