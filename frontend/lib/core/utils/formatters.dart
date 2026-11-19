import 'package:intl/intl.dart';

class AppFormatters {
  AppFormatters._();

  static final NumberFormat _currency = NumberFormat.decimalPattern('vi_VN');

  static String currency(num? amount) {
    return '${_currency.format(amount ?? 0)} đ';
  }

  static String date(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  static String dateStr(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd/MM/yyyy').format(parsed.toLocal());
  }
}

