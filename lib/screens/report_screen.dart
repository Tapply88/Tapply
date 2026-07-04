import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../services/db_service.dart';
import '../widgets/receipt_view.dart';

const _navy = Color(0xFF092762);

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  Future<bool> _confirmSupervisorPin(BuildContext context, String title) async {
    final pinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter a Supervisor PIN to continue.'),
            const SizedBox(height: 8),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final staff = DbService.findStaffByPin(pinCtrl.text);
              if (staff == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Wrong PIN')));
              } else if (staff.role != 'supervisor') {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Only supervisors can void receipts')));
              } else {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _showReceipt(BuildContext context, dynamic tx) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ReceiptView(tx: tx),
                      const SizedBox(height: 16),
                      if (tx.status == 'paid') ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), foregroundColor: Colors.red),
                          icon: const Icon(Icons.block, size: 16),
                          label: const Text('Void Receipt'),
                          onPressed: () async {
                            final confirmed = await _confirmSupervisorPin(ctx, 'Void This Receipt?');
                            if (!confirmed) return;
                            await DbService.voidTransaction(tx.id);
                            setDialogState(() {});
                            if (mounted) setState(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: DbService.transactions.listenable(),
      builder: (context, box, _) {
        final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
        final todayTotal = DbService.totalSalesToday();
        final byProduct = DbService.salesByProduct();
        final sortedEntries = byProduct.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        final allTx = DbService.transactions.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final lowStock = DbService.products.values.where((p) => p.stock <= 5).toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Sales Report')),
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
                      const Text('Today\'s Sales'),
                      const SizedBox(height: 4),
                      Text(currency.format(todayTotal), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              if (lowStock.isNotEmpty) ...[
                const SizedBox(height: 20),
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('⚠ Low Stock (${lowStock.length} products)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                        const SizedBox(height: 8),
                        ...lowStock.map((p) => Text('${p.name} — ${p.stock} left', style: TextStyle(color: Colors.red.shade800))),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Text('Sales by Payment Method', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...(() {
                final byMethod = DbService.salesByPaymentMethod();
                final sorted = byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                if (sorted.isEmpty) {
                  return [const Text('No transactions yet.', style: TextStyle(fontSize: 12, color: Colors.grey))];
                }
                return sorted
                    .map((e) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.payments_outlined, size: 18, color: _navy),
                          title: Text(paymentMethodLabel(e.key)),
                          trailing: Text(currency.format(e.value), style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                        ))
                    .toList();
              })(),
              const SizedBox(height: 20),
              const Text('Best-selling Products (all time)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...sortedEntries.map((e) => ListTile(
                    dense: true,
                    title: Text(e.key),
                    trailing: Text('${e.value} sold'),
                  )),
              const SizedBox(height: 20),
              const Text('Transaction History', style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('Tap to view full receipt', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 8),
              ...allTx.take(100).map((t) {
                final voided = t.status == 'void';
                return ListTile(
                  dense: true,
                  onTap: () => _showReceipt(context, t),
                  title: Text(
                    currency.format(t.total),
                    style: voided ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey) : null,
                  ),
                  subtitle: Text('${paymentMethodLabel(t.paymentMethod)} • ${DateFormat('dd MMM yyyy, HH:mm').format(t.createdAt)}'),
                  trailing: Text(
                    voided ? 'VOID' : t.status,
                    style: TextStyle(color: voided ? Colors.red : null, fontWeight: voided ? FontWeight.bold : null),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
