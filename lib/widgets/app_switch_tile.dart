import 'package:flutter/material.dart';

// A row with a switch on the right — looks like SwitchListTile, but only
// the switch itself toggles. Tapping the label (or its ⓘ) does nothing to
// the setting, so it can't be changed by accident while scrolling or
// reading the info bubble.
class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.secondary,
    this.contentPadding,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? secondary;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: contentPadding,
      leading: secondary,
      title: title,
      subtitle: subtitle,
      enabled: onChanged != null,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}
