import 'dart:convert';
import 'package:http/http.dart' as http;

/// PENTING: Server Key Midtrans TIDAK BOLEH ditaruh di app Flutter ini
/// (bisa dibongkar orang lain dari APK). App ini hanya manggil backend
/// kecil (lihat folder /server) yang nyimpen Server Key secara aman,
/// dan backend itu yang komunikasi ke Midtrans.
class MidtransService {
  // Ganti sesuai URL backend proxy kamu setelah di-deploy
  // (contoh: Railway/Render/Vercel). Untuk dev lokal di Codespaces,
  // ini bisa forwarded port dari server Node.js di folder /server.
  static const String backendBaseUrl = 'https://YOUR-BACKEND-URL.example.com';

  /// Minta Snap token dari backend, lalu buka snapRedirectUrl di WebView
  /// atau browser buat customer scan QRIS / bayar.
  static Future<Map<String, dynamic>> createTransaction({
    required String orderId,
    required int grossAmount,
    required String customerName,
  }) async {
    final res = await http.post(
      Uri.parse('$backendBaseUrl/create-transaction'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'order_id': orderId,
        'gross_amount': grossAmount,
        'customer_name': customerName,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Gagal bikin transaksi Midtrans: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Cek status pembayaran (dipanggil setelah customer selesai bayar,
  /// atau lewat polling / webhook di backend).
  static Future<String> checkStatus(String orderId) async {
    final res = await http.get(Uri.parse('$backendBaseUrl/status/$orderId'));
    if (res.statusCode != 200) {
      throw Exception('Gagal cek status: ${res.body}');
    }
    final data = jsonDecode(res.body);
    return data['transaction_status'] as String; // e.g. "settlement", "pending"
  }
}
