import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/db_service.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final todayTotal = DbService.totalSalesToday();
    final byProduct = DbService.salesByProduct();
    final sortedEntries = byProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final allTx = DbService.transactions.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Penjualan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Penjualan Hari Ini'),
                  const SizedBox(height: 4),
                  Text(currency.format(todayTotal), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Produk Terlaris (semua waktu)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...sortedEntries.map((e) => ListTile(
                dense: true,
                title: Text(e.key),
                trailing: Text('${e.value} terjual'),
              )),
          const SizedBox(height: 20),
          const Text('Riwayat Transaksi', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...allTx.take(50).map((t) => ListTile(
                dense: true,
                title: Text(currency.format(t.total)),
                subtitle: Text('${t.paymentMethod} • ${DateFormat('dd MMM yyyy, HH:mm').format(t.createdAt)}'),
                trailing: Text(t.status),
              )),
        ],
      ),
    );
  }
}
