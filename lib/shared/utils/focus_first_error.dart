import 'package:flutter/material.dart';

/// Submit helpers: when something required is missing, take the customer to
/// it instead of just showing an error somewhere they may not be looking.

/// Validates [formKey]. When invalid, scrolls to the FIRST invalid field (top
/// to bottom) and puts the keyboard cursor in it. Returns true when valid.
///
/// Use instead of `_formKey.currentState!.validate()`.
bool validateAndFocus(GlobalKey<FormState> formKey) {
  final form = formKey.currentState;
  if (form == null) return true;
  if (form.validate()) return true;
  // Wait one frame so the error text is laid out before we scroll to it.
  WidgetsBinding.instance.addPostFrameCallback((_) => focusFirstInvalid(formKey.currentContext));
  return false;
}

/// Finds the first [FormField] under [root] that currently shows an error,
/// scrolls it into view and focuses its text input (if it has one).
void focusFirstInvalid(BuildContext? root) {
  if (root == null || !root.mounted) return;
  FormFieldState<dynamic>? first;
  void visit(Element e) {
    if (first != null) return;
    if (e is StatefulElement) {
      final s = e.state;
      if (s is FormFieldState && s.hasError) {
        first = s;
        return;
      }
    }
    e.visitChildren(visit);
  }

  (root as Element).visitChildren(visit);
  final field = first;
  if (field == null || !field.mounted) return;

  FocusNode? node;
  void findInput(Element e) {
    if (node != null) return;
    if (e is StatefulElement) {
      final s = e.state;
      if (s is EditableTextState) {
        node = s.widget.focusNode;
        return;
      }
    }
    e.visitChildren(findInput);
  }

  (field.context as Element).visitChildren(findInput);
  revealContext(field.context);
  node?.requestFocus();
}

/// Scrolls the widget behind [context] to the upper part of the screen.
void revealContext(BuildContext context) {
  if (!context.mounted) return;
  Scrollable.ensureVisible(
    context,
    alignment: 0.15,
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
  );
}

/// For screens that validate by hand (no [Form]): scroll to the widget tagged
/// with [key] and, when it is a text input, focus it with [focus].
///
///   if (address == null) { _warn('Select an address'); revealField(_addressKey); return; }
void revealField(GlobalKey key, {FocusNode? focus}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = key.currentContext;
    if (ctx != null) revealContext(ctx);
    focus?.requestFocus();
  });
}
