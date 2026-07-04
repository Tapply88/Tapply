import 'db_service.dart';

/// Dictionary terjemahan UI app (BUKAN nama menu/produk atau nama promo — itu tetap
/// apa adanya sesuai input user). Panggil AppStrings.t('key') buat ambil teks sesuai
/// bahasa yang aktif di Setelan.
class AppStrings {
  static const Map<String, Map<String, String>> _strings = {
    // Bottom nav
    'nav_kasir': {'id': 'POS', 'en': 'POS'},
    'nav_member': {'id': 'Member', 'en': 'Member'},
    'nav_inventory': {'id': 'Inventory', 'en': 'Inventory'},
    'nav_laporan': {'id': 'Laporan', 'en': 'Report'},
    'nav_setelan': {'id': 'Setelan', 'en': 'Settings'},
    // Shift gate
    'mulai_shift': {'id': 'Mulai Shift', 'en': 'Start Shift'},
    'nama_kasir': {'id': 'Nama Kasir', 'en': 'Cashier Name'},
    'email_kasir': {'id': 'Email Kasir', 'en': 'Cashier Email'},
    'modal_awal': {'id': 'Modal Awal (Rp)', 'en': 'Starting Cash'},
    // Cashier action buttons
    'save_bill': {'id': 'Save Bill', 'en': 'Save Bill'},
    'order_dapur': {'id': 'Order Dapur', 'en': 'Kitchen Order'},
    'print_check': {'id': 'Print Check', 'en': 'Print Check'},
    'charge': {'id': 'Charge', 'en': 'Charge'},
    'tambah_pelanggan': {'id': '+ Tambah Pelanggan', 'en': '+ Add Customer'},
    'item_custom': {'id': 'Item Custom', 'en': 'Custom Item'},
    // Settings
    'bahasa': {'id': 'Bahasa', 'en': 'Language'},
    'keamanan': {'id': 'Keamanan', 'en': 'Security'},
    'pin_manager': {'id': 'PIN Manager (buat cancel item)', 'en': 'Manager PIN (for canceling items)'},
    // Common actions
    'simpan': {'id': 'Simpan', 'en': 'Save'},
    'batal': {'id': 'Batal', 'en': 'Cancel'},
    'tutup': {'id': 'Tutup', 'en': 'Close'},
    'hapus': {'id': 'Hapus', 'en': 'Delete'},
    'cari': {'id': 'Cari', 'en': 'Search'},
  };

  static String t(String key) {
    final lang = DbService.language;
    return _strings[key]?[lang] ?? key;
  }
}
