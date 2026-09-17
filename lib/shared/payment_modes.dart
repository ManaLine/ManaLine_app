/// The payment modes, in one place, because there are four consumers of them.
///
/// WHY THIS FILE EXISTS. `payment_mode_enum` gained GPay, PhonePe and Paytm on
/// 2026-09-17, at the Owner's direction and against page 4 of the design
/// document, which writes G℗ and P℗ against individual payments. Before that
/// the vocabulary was spelled out twice in `lib/` -- a list and a key map in
/// OW-006's collection form, and four hardcoded `byMode('...')` calls in the
/// agent dashboard -- and the second copy did not have the new values.
///
/// The consequence was not cosmetic. `byMode` sums the splits matching one
/// mode, and `todaysCollectionsTotal` adds the buckets up; a payment in a mode
/// nobody asks for lands in no bucket and disappears from the agent's own
/// total for the day. That is CLAUDE.md's recurring failure exactly -- "a
/// change correct in itself while a second consumer of the same column went on
/// using it the old way" -- and on a money path.
///
/// So: one list, one key map, one definition of which modes are online, and
/// `schema_snapshot_test` checks the list against the database enum.
library;

/// Every mode the database accepts, matching `payment_mode_enum`.
///
/// ORDER IS THE FORM'S ORDER, and Cash is first because it is most of every
/// day -- 349 of the 355 live splits at the time of writing.
const manaPaymentModes = <String>[
  'Cash',
  'GPay',
  'PhonePe',
  'Paytm',
  'Bank Transfer',
  'Cheque',
  'UPI',
];

/// The modes a collection form offers.
///
/// UPI IS DELIBERATELY ABSENT, and deliberately still in [manaPaymentModes].
/// Six live payments carry it, recorded before the app could ask which app the
/// money came through, and they must keep reading back as what they are. But
/// offering it alongside GPay, PhonePe and Paytm would ask an agent standing
/// at a doorstep to choose between "PhonePe" and "UPI" for a PhonePe payment,
/// which is a question with no right answer.
const manaOfferedPaymentModes = <String>[
  'Cash',
  'GPay',
  'PhonePe',
  'Paytm',
  'Bank Transfer',
  'Cheque',
];

/// The ℗ modes -- page 5: "© - Cash / ℗ - Online Payment (Gpay,Phonepe,
/// Paytm)".
///
/// UPI is here because that is what it always meant. Bank Transfer and Cheque
/// are NOT: a cheque is not an online payment, and neither is money moved at a
/// branch. They are their own lines, as they are on the agent's dashboard.
const manaOnlinePaymentModes = <String>{'GPay', 'PhonePe', 'Paytm', 'UPI'};

/// A mode's translation key.
///
/// A switch rather than a computed lowercase-and-underscore, so that adding a
/// mode without adding a word for it fails to compile here instead of
/// rendering a raw key on somebody's screen.
String manaPaymentModeKey(String mode) => switch (mode) {
      'Cash' => 'cash',
      'UPI' => 'upi',
      'Cheque' => 'cheque',
      'Bank Transfer' => 'bank_transfer',
      'GPay' => 'gpay',
      'PhonePe' => 'phonepe',
      'Paytm' => 'paytm',
      // A mode this build has never heard of, which can only mean the database
      // gained one. Its own name reads better than a blank or a raw key.
      _ => mode,
    };
