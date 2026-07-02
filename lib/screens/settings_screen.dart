import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/db_service.dart';

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
  late bool _roundingEnabled;
  late int _roundingNearest;

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
    _roundingEnabled = DbService.roundingEnabled;
    _roundingNearest = DbService.roundingNearest;
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
          const Text('Tax, Service, Diskon & Pembulatan', style: TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Opsional. Nanti bisa juga diatur dari dashboard admin (website) — untuk sekarang atur di sini.',
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
            title: const Text('Diskon Otomatis'),
            value: _discountEnabled,
            onChanged: (v) => setState(() => _discountEnabled = v),
          ),
          if (_discountEnabled)
            TextField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Persentase Diskon (%)'),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _navy,
            title: const Text('Pembulatan Total'),
            value: _roundingEnabled,
            onChanged: (v) => setState(() => _roundingEnabled = v),
          ),
          if (_roundingEnabled)
            DropdownButtonFormField<int>(
              initialValue: _roundingNearest,
              decoration: const InputDecoration(labelText: 'Bulatkan ke kelipatan'),
              items: const [100, 500, 1000]
                  .map((v) => DropdownMenuItem(value: v, child: Text('Rp $v')))
                  .toList(),
              onChanged: (v) => setState(() => _roundingNearest = v ?? 100),
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
