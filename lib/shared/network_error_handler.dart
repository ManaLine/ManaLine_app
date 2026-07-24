import 'package:flutter/material.dart';

/// One consistent way to run a network call from any screen and surface
/// its failure. Every LR screen's submit/verify/send action should route
/// through this rather than its own bespoke try/catch — the goal is that
/// a dropped connection looks and behaves the same everywhere in the app,
/// not seven different undefined behaviors depending on which screen the
/// person happened to be on when their connection dropped.
///
/// Usage:
///   final result = await NetworkErrorHandler.run(context, () async {
///     return await someApiCall();
///   });
///   if (result == null) return; // failed — error already shown, stay put
///   // ...use result, proceed...
class NetworkErrorHandler {
  NetworkErrorHandler._();

  /// Runs [action]. On success, returns its result. On failure, shows a
  /// SnackBar (connectivity-worded if the error looks like a dropped
  /// connection/timeout, generic otherwise) with a Retry action, and
  /// returns null. Callers MUST treat a null result as "abort, remain on
  /// this screen" — never proceed as if the call succeeded.
  static Future<T?> run<T>(
    BuildContext context,
    Future<T> Function() action, {
    String genericErrorMessage = 'Something went wrong. Please try again.',
  }) async {
    try {
      return await action();
    } catch (e) {
      if (!context.mounted) return null;

      final message = _looksLikeConnectivityError(e)
          ? 'No internet connection. Please check your network and try again.'
          : genericErrorMessage;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => run(context, action, genericErrorMessage: genericErrorMessage),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return null;
    }
  }

  static bool _looksLikeConnectivityError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('timeout') ||
        s.contains('network') ||
        s.contains('failed host lookup') ||
        s.contains('connection') ||
        s.contains('clientexception');
  }
}
