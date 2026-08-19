import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How long any single Supabase call may hang before it is treated as failed.
///
/// PostgREST and the Functions client have NO client-side deadline of their
/// own, so a request made on a dying connection — the tea-shop captive
/// portal, a cell that hands over mid-request — never completes and never
/// errors. The screen that made it spins forever with nothing to cancel.
/// This is deliberately generous: a village 2G round trip is genuinely slow,
/// and cutting a working request short would be worse than waiting.
const Duration kManaQueryTimeout = Duration(seconds: 20);

/// How long an error SnackBar stays up. Long enough to read a sentence on a
/// handset held at arm's length, short enough not to sit over a button.
const Duration kErrorSnackDuration = Duration(seconds: 6);

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
      // Every call routed through here inherits the deadline, so no screen
      // has to remember to add one.
      return await action().timeout(kManaQueryTimeout);
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
      final message = e is TimeoutException
          ? 'The server did not respond. Check your connection and try again.'
          : _isServerReachedError(e)
          ? _serverErrorMessage(e, genericErrorMessage)
          : _looksLikeConnectivityError(e)
              ? 'No internet connection. Please check your network and try again.'
              : genericErrorMessage;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final controller = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => run(context, action, genericErrorMessage: genericErrorMessage),
          ),
          duration: kErrorSnackDuration,
        ),
      );

      // A SnackBar carrying an action never starts its own auto-dismiss timer
      // (Flutter 3.44) — `duration` is simply ignored and the bar stays up
      // until something else replaces it. Found on a live handset: a failed
      // save left the error sitting over the Save buttons on Add a Customer
      // for six minutes, and swiping did not clear it, so the screen could
      // not be used. Every error in the app goes out through here, so the
      // timer is started here rather than at 75 call sites.
      var closed = false;
      unawaited(controller.closed.then((_) => closed = true));
      Timer(kErrorSnackDuration, () {
        if (!closed) controller.close();
      });
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
      final constraint = _constraintMessage(e);
      if (constraint != null) return constraint;
      return e.message.isNotEmpty ? e.message : genericErrorMessage;
    }
    return genericErrorMessage;
  }

  /// Turns a Postgres integrity violation into something an Owner can act on.
  ///
  /// Without this, `e.message` reaches the screen verbatim and a field user
  /// is shown
  ///   duplicate key value violates unique constraint "uq_persons_mobile_number"
  /// which names neither the person, nor the field, nor what to do next.
  /// Seen live while entering a pre-existing loan for someone the book had
  /// already registered. Anything not listed here still falls through to the
  /// raw text — a wrong friendly message would be worse than a technical
  /// true one.
  static String? _constraintMessage(PostgrestException e) {
    // 23505 unique_violation. Match on the constraint name inside the text,
    // because PostgREST does not expose `constraint_name` separately.
    if (e.code != '23505') return null;
    final text = e.message;
    if (text.contains('uq_persons_mobile_number')) {
      return 'That mobile number is already registered to someone else. '
          'Search for them by name instead of adding a new person.';
    }
    if (text.contains('uq_business_members_person_business_role')) {
      return 'This person is already in this business in that role.';
    }
    if (text.contains('uq_oal_business_location')) {
      return 'That village is already attached to an area in this business.';
    }
    if (text.contains('persons_mlid_key')) {
      return 'Could not allocate an ID for this person. Please try again.';
    }
    return null;
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
