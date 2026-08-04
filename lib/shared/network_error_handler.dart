import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

      // FunctionException/PostgrestException mean the request reached
      // Supabase — the failure is server-side (missing/erroring Edge
      // Function, RLS denial, bad request), not a dropped connection.
      // Showing "no internet" for these actively hides the real problem
      // (e.g. an Edge Function that was never deployed) behind a message
      // that sends the person to check their WiFi instead of reporting
      // the bug. Only genuine transport-layer failures (DNS, socket,
      // timeout — thrown before any response is received) get the
      // connectivity-worded message below.
      final message = _isServerReachedError(e)
          ? _serverErrorMessage(e, genericErrorMessage)
          : _looksLikeConnectivityError(e)
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

  static bool _isServerReachedError(Object e) => e is FunctionException || e is PostgrestException;

  static String _serverErrorMessage(Object e, String genericErrorMessage) {
    if (e is FunctionException) {
      if (e.status == 404) {
        return 'This action isn\'t available yet (server function not found). Please try again later.';
      }
      if (e.status == 429) {
        // Edge functions return 429 + RATE_LIMITED when the auth rate
        // limiter (auth_rate_limits, batch D) refuses the call.
        return 'Too many attempts. Please wait a few minutes and try again.';
      }
      return 'Server error (${e.status}). Please try again later.';
    }
    if (e is PostgrestException) {
      if (isSessionExpired(e)) return sessionExpiredMessage;
      return e.message.isNotEmpty ? e.message : genericErrorMessage;
    }
    return genericErrorMessage;
  }

  /// The session token died mid-use.
  ///
  /// The minted JWT has a 1-hour TTL and there is no refresh endpoint, so
  /// this is a normal end-of-session event rather than a fault. PostgREST
  /// reports it as PGRST303; the raw text is "JWT expired", which means
  /// nothing to an Owner standing in a field.
  static bool isSessionExpired(Object e) {
    if (e is PostgrestException) {
      if (e.code == 'PGRST303') return true;
      return e.message.toLowerCase().contains('jwt expired');
    }
    return e.toString().toLowerCase().contains('jwt expired');
  }

  static const sessionExpiredMessage =
      'Your session has timed out. Enter your PIN to continue.';

  /// NARROWED. This used to match a bare 'connection' anywhere in the
  /// error text, which swallowed unrelated failures into "No internet
  /// connection" and sent people to check their WiFi over a bug that had
  /// nothing to do with the network — including, on a real handset, a
  /// missing android.permission.INTERNET, which presents as a socket
  /// failure and is not a connectivity problem the person can fix.
  ///
  /// Now only matches the transport-layer failures that genuinely mean
  /// "the request never reached a server".
  static bool _looksLikeConnectivityError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('connection refused') ||
        s.contains('connection closed') ||
        s.contains('connection reset') ||
        s.contains('connection timed out') ||
        s.contains('timeoutexception') ||
        s.contains('network is unreachable') ||
        s.contains('clientexception');
  }
}
