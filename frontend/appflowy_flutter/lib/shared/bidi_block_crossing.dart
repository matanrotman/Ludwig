import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// [fork:bidi] Hands the visual block-crossing experiment's switch to the
/// editor fork, which owns the arrow-key commands but cannot read Ludwig's
/// preferences.
///
/// The question it settles is one with no convention to copy: at the boundary
/// between an English paragraph and a Hebrew one, "left" means backward in the
/// first and forward in the second, so each paragraph hands the caret straight
/// back and arrow-left ping-pongs between them.
///
///  * **off** (default) — the paragraph decides. Right in a document that does
///    not mix directions, bouncing in one that does.
///  * **on** — leftward movement always arrives at the neighbouring paragraph's
///    right edge and keeps marching left. Nothing bounces, but two paragraphs
///    of opposite direction can be circled rather than passed through.
///
/// Toggle it live at Settings → Feature Flags → `visualBlockCrossing` (a debug
/// build only; the page is `kDebugMode`-gated upstream). Deliberately a switch
/// rather than a decision: see `specs/bidi-caret-movement.md`.
void applyVisualBlockCrossingFlag() {
  VisualCaretTraversal.crossBlocksVisually =
      FeatureFlag.visualBlockCrossing.isOn;
}
