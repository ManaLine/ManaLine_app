import 'package:flutter/material.dart';

/// The glyphs that carry a meaning, in one place.
///
/// WHY THIS FILE EXISTS. `Icons.savings_outlined` -- the piggy bank -- was
/// drawn for BOTH an investor and a cheti, on nine call sites across six
/// files, and on OW-012 the two sat on the same screen: an investor count
/// chip in the header and a cheti button in the actions, identical. Reported
/// from a handset as exactly that.
///
/// A symbol that means two things means neither. Naming them here is what
/// makes the ninth call site a decision rather than a copy of the eighth.
///
/// ONLY the icons that carry a meaning belong here. A back arrow, a search
/// magnifier and an expand chevron mean what Material says they mean
/// everywhere in the world, and putting them behind a name would be a second
/// vocabulary to learn for no gain.
abstract final class ManaIcons {
  /// An INVESTOR: somebody who hands money to the business.
  ///
  /// The Owner asked for "a hand giving out cash", and volunteer_activism is
  /// the open offering palm -- the closest Material has, and it reads at 18dp
  /// on a cheap screen, which a more literal hand-and-banknotes drawing would
  /// not. It is the only outstretched-hand glyph in the set that is about
  /// giving rather than stopping (front_hand), shaking (handshake) or holding
  /// a house (real_estate_agent).
  ///
  /// If this needs to be a rupee note on a palm, that is a custom asset
  /// rather than another Material name, and it belongs here when it is drawn.
  static const IconData investor = Icons.volunteer_activism_outlined;

  /// A CHETI: a chit fund. Instalments paid in until the lumpsum is availed.
  ///
  /// The piggy bank keeps this meaning, because saving up in instalments is
  /// what it has always drawn. What was wrong was never this glyph -- it was
  /// the investor borrowing it.
  static const IconData cheti = Icons.savings_outlined;
}
