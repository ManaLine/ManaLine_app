/// Typed `extra` payload for navigating to LR-007 (First Login) from a
/// recovery flow. Replaces the earlier bare `extra: true` convention
/// (which only supported LR-009's step-down case) — LR-010's exit needs
/// to also carry a pre-filled mobile number and a success toast, and a
/// second bool/String-mix on the same `extra` slot is exactly the kind
/// of thing that silently breaks when a third caller shows up. One
/// small typed class instead.
class LoginStepDownArgs {
  final bool stepDownFromFailedPin;
  final String? prefilledMobile;
  final String? successToast;

  const LoginStepDownArgs({
    this.stepDownFromFailedPin = false,
    this.prefilledMobile,
    this.successToast,
  });
}
