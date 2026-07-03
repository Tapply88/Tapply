import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/db_service.dart';
import 'promo_screen.dart';

const _navy = Color(0xFF092762);
const _grey = Color(0xFFCFCFCF);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _footerCtrl;
  String? _logoBase64;

  late bool _taxEnabled;
  late final TextEditingController _taxCtrl;
  late bool _serviceEnabled;
  late final TextEditingController _serviceCtrl;
  late bool _discountEnabled;
  late final TextEditingController _discountCtrl;
  late final TextEditingController _promoNameCtrl;
  late bool _roundingEnabled;
  late int _roundingNearest;
  late bool _queueNumberEnabled;
  late final TextEditingController _queueStartCtrl;
  final _queueTodayCtrl = TextEditingController();
  late bool _showZeroAmountRows;
  late bool _printCheckEnabled;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: DbService.businessName);
    _addressCtrl = TextEditingController(text: DbService.businessAddress);
    _phoneCtrl = TextEditingController(text: DbService.businessPhone);
    _footerCtrl = TextEditingController(text: DbService.receiptFooterText);
    _logoBase64 = DbService.businessLogoBase64;

    _taxEnabled = DbService.taxEnabled;
    _taxCtrl = TextEditingController(text: DbService.taxPercent.toStringAsFixed(1));
    _serviceEnabled = DbService.serviceEnabled;
    _serviceCtrl = TextEditingController(text: DbService.servicePercent.toStringAsFixed(1));
    _discountEnabled = DbService.discountEnabled;
    _discountCtrl = TextEditingController(text: DbService.discountPercent.toStringAsFixed(1));
    _promoNameCtrl = TextEditingController(text: DbService.discountPromoName);
    _roundingEnabled = DbService.roundingEnabled;
    _roundingNearest = DbService.roundingNearest;
    _queueNumberEnabled = DbService.queueNumberEnabled;
    _queueStartCtrl = TextEditingController(text: '${DbService.queueStartNumber}');
    _showZeroAmountRows = DbService.showZeroAmountRows;
    _printCheckEnabled = DbService.printCheckEnabled;
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);
    await DbService.setBusinessLogo(b64);
    setState(() => _logoBase64 = b64);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logo bisnis disimpan')));
  }

  Future<void> _removeLogo() async {
    await DbService.setBusinessLogo(null);
    setState(() => _logoBase64 = null);
  }

  Future<void> _saveBusinessProfile() async {
    await DbService.updateBusinessProfile(
      businessName: _nameCtrl.text.trim(),
      businessAddress: _addressCtrl.text.trim(),
      businessPhone: _phoneCtrl.text.trim(),
      receiptFooterText: _footerCtrl.text.trim().isEmpty ? 'Terima kasih!' : _footerCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil bisnis disimpan')));
  }

  Future<void> _saveTaxSettings() async {
    await DbService.updateSettings(
      taxEnabled: _taxEnabled,
      taxPercent: double.tryParse(_taxCtrl.text) ?? 0,
      serviceEnabled: _serviceEnabled,
      servicePercent: double.tryParse(_serviceCtrl.text) ?? 0,
      discountEnabled: _discountEnabled,
      discountPercent: double.tryParse(_discountCtrl.text) ?? 0,
      discountPromoName: _promoNameCtrl.text.trim(),
      roundingEnabled: _roundingEnabled,
      roundingNearest: _roundingNearest,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengaturan total disimpan')));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setelan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Profil Bisnis', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Muncul di bagian atas struk (logo, nama, alamat, no. telp).',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  border: Border.all(color: _navy, width: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  color: _grey.withValues(alpha: 0.3),
                ),
                child: _logoBase64 != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(base64Decode(_logoBase64!), fit: BoxFit.contain),
                      )
                    : const Icon(Icons.storefront, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                      onPressed: _pickLogo,
                      child: Text(_logoBase64 != null ? 'Ganti Logo' : 'Upload Logo Bisnis'),
                    ),
                    if (_logoBase64 != null)
                      TextButton(
                        onPressed: _removeLogo,
                        child: const Text('Hapus logo', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nama bisnis')),
          const SizedBox(height: 8),
          TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Alamat'), maxLines: 2),
          const SizedBox(height: 8),
          TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'No. Telepon'), keyboardType: TextInputType.phone),
          const SizedBox(height: 8),
          TextField(controller: _footerCtrl, decoration: const InputDecoration(labelText: 'Teks penutup struk', hintText: 'Terima kasih!')),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: _saveBusinessProfile,
            child: const Text('Simpan Profil Bisnis'),
          ),
          const Divider(height: 40),
          const Text('Promo', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Bikin promo dengan tanggal berlaku, jenis diskon (persen/nominal), dan minimum pembelian. '
            'Kalau ada promo yang valid saat checkout, itu dipakai otomatis (yang diskonnya paling besar kalau ada beberapa).',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PromoScreen())),
            icon: const Icon(Icons.local_offer_outlined, size: 18),
            label: const Text('Kelola Promo'),
          ),
          const Divider(height: 40),
          const Text('Tax, Service, Diskon Manual & Pembulatan', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Diskon manual di bawah ini dipakai kalau TIDAK ada promo bertanggal yang sedang valid.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Tax'),
            value: _taxEnabled,
            onChanged: (v) => setState(() => _taxEnabled = v),
          ),
          if (_taxEnabled)
            TextField(
              controller: _taxCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Persentase Tax (%)'),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Service Charge'),
            value: _serviceEnabled,
            onChanged: (v) => setState(() => _serviceEnabled = v),
          ),
          if (_serviceEnabled)
            TextField(
              controller: _serviceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Persentase Service (%)'),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Automatic Discount'),
            value: _discountEnabled,
            onChanged: (v) => setState(() => _discountEnabled = v),
          ),
          if (_discountEnabled) ...[
            TextField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Discount percentage (%)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _promoNameCtrl,
              decoration: const InputDecoration(labelText: 'Promo name (optional)', hintText: 'e.g. Ramadan Promo'),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Total Rounding'),
            value: _roundingEnabled,
            onChanged: (v) => setState(() => _roundingEnabled = v),
          ),
          if (_roundingEnabled)
            DropdownButtonFormField<int>(
              initialValue: _roundingNearest,
              decoration: const InputDecoration(labelText: 'Round to nearest'),
              items: const [100, 500, 1000]
                  .map((v) => DropdownMenuItem(value: v, child: Text('Rp $v')))
                  .toList(),
              onChanged: (v) => setState(() => _roundingNearest = v ?? 100),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Nomor Antrian di Struk'),
            subtitle: const Text('Opsional — nomor urut harian di bagian paling atas struk', style: TextStyle(fontSize: 11)),
            value: _queueNumberEnabled,
            onChanged: (v) async {
              setState(() => _queueNumberEnabled = v);
              await DbService.setQueueNumberEnabled(v);
            },
          ),
          if (_queueNumberEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queueStartCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Mulai dari (tiap hari baru)', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _navy),
                  onPressed: () async {
                    final n = int.tryParse(_queueStartCtrl.text) ?? 1;
                    await DbService.setQueueStartNumber(n);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nomor mulai harian disimpan')));
                  },
                  child: const Text('Simpan'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queueTodayCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Set nomor antrian HARI INI sekarang ke', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                  onPressed: () async {
                    final n = int.tryParse(_queueTodayCtrl.text);
                    if (n == null) return;
                    await DbService.resetQueueCounterToday(n);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nomor antrian berikutnya: $n')));
                  },
                  child: const Text('Terapkan'),
                ),
              ],
            ),
            const Text(
              'Bisa juga isi manual per transaksi (kode custom) langsung di kasir — gak harus angka urut.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Selalu Tampilkan Tax/Service/Rounding'),
            subtitle: const Text('Kalau dimatikan, baris itu disembunyikan waktu nilainya Rp0', style: TextStyle(fontSize: 11)),
            value: _showZeroAmountRows,
            onChanged: (v) async {
              setState(() => _showZeroAmountRows = v);
              await DbService.setShowZeroAmountRows(v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Tombol Print Check'),
            subtitle: const Text('Opsional — preview bill sebelum bayar (beda dari struk final setelah bayar)', style: TextStyle(fontSize: 11)),
            value: _printCheckEnabled,
            onChanged: (v) async {
              setState(() => _printCheckEnabled = v);
              await DbService.setPrintCheckEnabled(v);
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: _saveTaxSettings,
            child: const Text('Simpan Pengaturan Total'),
          ),
        ],
      ),
    );
  }
}
