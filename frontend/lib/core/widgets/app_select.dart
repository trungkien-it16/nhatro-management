import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../theme/app_typography.dart';

class AppSelectOption<T> {
  final T value;
  final String label;
  const AppSelectOption({required this.value, required this.label});
}

class AppSelect<T> extends StatelessWidget {
  final String? label;
  final T value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T?> onChanged;
  final double? width;

  const AppSelect({
    super.key,
    this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.width = 190,
  });

  @override
  Widget build(BuildContext context) {
    final dropdown = DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      style: AppTypography.body,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSecondary),
      decoration: InputDecoration(
        labelText: label,
      ),
      items: [
        for (final opt in options)
          DropdownMenuItem<T>(
            value: opt.value,
            child: Text(
              opt.label,
              style: AppTypography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );

    if (width == null) return dropdown;
    return SizedBox(width: width, child: dropdown);
  }
}

