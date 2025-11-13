import 'package:flutter/material.dart';

// Simplified RadioWidget compatible with Flutter 3.32
// Removed dependency on internal RadioGroup APIs

class RadioWidget<T> extends StatelessWidget {
  final T value;
  final String title;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final bool tristate;
  final EdgeInsetsGeometry? padding;
  final MainAxisSize mainAxisSize;

  const RadioWidget({
    super.key,
    required this.value,
    required this.title,
    this.groupValue,
    this.onChanged,
    this.tristate = false,
    this.padding,
    this.mainAxisSize = MainAxisSize.min,
  });

  @override
  Widget build(BuildContext context) {
    final checked = value == groupValue;
    
    return InkWell(
      onTap: () {
        if (onChanged == null) return;
        if (checked && tristate) {
          onChanged!(null);
        } else if (!checked) {
          onChanged!(value);
        }
      },
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Row(
          mainAxisSize: mainAxisSize,
          children: [
            Radio<T>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Text(title),
          ],
        ),
      ),
    );
  }
}

class WrapRadioOptionsGroup<T> extends StatelessWidget {
  final String groupTitle;
  final Map<T, String> options;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final EdgeInsetsGeometry? itemPadding;

  const WrapRadioOptionsGroup({
    super.key,
    required this.groupTitle,
    required this.options,
    this.groupValue,
    this.onChanged,
    this.itemPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groupTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(
              groupTitle,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            children: options.entries.map((entry) {
              return RadioWidget<T>(
                value: entry.key,
                title: entry.value,
                groupValue: groupValue,
                onChanged: onChanged,
                padding: itemPadding ?? const EdgeInsets.only(right: 10),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
