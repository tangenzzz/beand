import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';

// Settings → Beans → Form: show/hide fields of the bean form and reorder
// them by dragging. Photo, name and roastery stay fixed at the top. Hidden
// fields keep their stored values, they are only hidden in the form.
class BeansFormSettingsScreen extends StatelessWidget {
  const BeansFormSettingsScreen({super.key});

  static const _fixedFields = ['Photo', 'Name', 'Roastery'];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final fields = settings.beanFormFields;
    return Scaffold(
      appBar: AppBar(title: const Text('Form')),
      // ONE card: the fixed fields on top, one divider, then the movable
      // ones — no lines between the entries themselves.
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('Always shown'),
                for (final name in _fixedFields)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.dividerInset,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: context.colors.textTertiary,
                          size: 20,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          name,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                const _RowDivider(),
                const _SectionLabel('Fields · drag to reorder'),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: settings.reorderBeanFormFields,
                  proxyDecorator: (child, _, _) => Material(
                    color: context.colors.card,
                    elevation: 6,
                    child: child,
                  ),
                  children: [
                    for (var i = 0; i < fields.length; i++)
                      _FieldRow(
                        key: ValueKey(fields[i]),
                        index: i,
                        field: fields[i],
                        visible: settings.isBeanFormFieldVisible(fields[i]),
                        onChanged: (v) =>
                            settings.setBeanFormFieldVisible(fields[i], v),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.index,
    required this.field,
    required this.visible,
    required this.onChanged,
  });

  final int index;
  final BeanFormField field;
  final bool visible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: 4,
              right: AppSpacing.dividerInset,
            ),
            child: Row(
              children: [
                // Only the handle starts dragging, so the switch stays free.
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      Icons.drag_handle,
                      color: context.colors.textTertiary,
                      size: 22,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    field.label,
                    style: TextStyle(
                      color: visible
                          ? context.colors.textPrimary
                          : context.colors.textTertiary,
                      fontSize: 15,
                    ),
                  ),
                ),
                Switch(value: visible, onChanged: onChanged),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: AppSpacing.dividerInset,
    endIndent: AppSpacing.dividerInset,
    color: context.colors.divider,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.dividerInset,
        16,
        AppSpacing.dividerInset,
        6,
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.colors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
