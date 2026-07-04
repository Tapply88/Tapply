import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/shift.dart';
import '../services/db_service.dart';
import '../widgets/receipt_view.dart';

const _navy = Color(0xFF092762);

class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _dateFmt = DateFormat('dd MMM yyyy, HH:mm');

  Future<void> _startShift() async {
    final ctrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start Shift', style: TextStyle(color: _navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cashier: ${DbService.currentCashierName.isEmpty ? "(not set)" : DbService.currentCashierName}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Starting Cash (Rp)'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _navy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start Shift'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final startingCash = int.tryParse(ctrl.text) ?? 0;
      await DbService.startShift(startingCash: startingCash);
      setState(() {});
    }
  }

  Future<void> _endShift(Shift shift) async {
    final expected = DbService.expectedCashForShift(shift);
    final countedCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final counted = int.tryParse(countedCtrl.text);
          final diff = counted != null ? counted - expected : null;
          return AlertDialog(
            title: const Text('End Shift & Settlement', style: TextStyle(color: _navy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow('Starting Cash', shift.startingCash),
                  ...DbService.salesDuringShift(shift).entries.map((e) => _summaryRow(paymentMethodLabel(e.key), e.value)),
                  const Divider(),
                  _summaryRow('Expected Cash in Drawer', expected, bold: true),
                  const SizedBox(height: 12),
                  TextField(
                    controller: countedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Actual Cash Counted (Rp)'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (diff != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      diff == 0
                          ? 'Spot on! No difference.'
                          : diff > 0
                              ? 'Over Rp${_currency.format(diff).replaceFirst("Rp ", "")}'
                              : 'Short Rp${_currency.format(diff.abs()).replaceFirst("Rp ", "")}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: diff == 0 ? Colors.green : (diff > 0 ? Colors.blue : Colors.red),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _navy),
                onPressed: counted == null
                    ? null
                    : () async {
                        await DbService.endShift(endingCashCounted: counted, note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});
                      },
                child: const Text('Close Shift'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _viewShiftDetail(Shift shift) {
    final expected = shift.status == 'closed' ? DbService.expectedCashForShift(shift) : null;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(shift.cashierName.isEmpty ? 'Cashier' : shift.cashierName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy)),
                  Text('Started: ${_dateFmt.format(shift.startTime)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (shift.endTime != null) Text('Ended: ${_dateFmt.format(shift.endTime!)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const Divider(height: 20),
                  _summaryRow('Starting Cash', shift.startingCash),
                  ...DbService.salesDuringShift(shift).entries.map((e) => _summaryRow(paymentMethodLabel(e.key), e.value)),
                  if (expected != null) ...[
                    const Divider(),
                    _summaryRow('Expected Cash', expected, bold: true),
                    _summaryRow('Cash Counted', shift.endingCashCounted ?? 0, bold: true),
                    _summaryRow('Difference', (shift.endingCashCounted ?? 0) - expected, bold: true),
                  ],
                  if (shift.note != null && shift.note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Note: ${shift.note}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                  const SizedBox(height: 16),
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
      ),
    );
  }

  Widget _summaryRow(String label, int amount, {bool bold = false}) {
    final style = TextStyle(color: _navy, fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 14 : 13);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(_currency.format(amount), style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = DbService.currentOpenShift;
    final history = DbService.shiftHistory.where((s) => s.status == 'closed').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Shift')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (open == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No Active Shift', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                    const SizedBox(height: 8),
                    const Text('Start a shift to record starting cash and settle up later.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _navy),
                      onPressed: _startShift,
                      child: const Text('Start Shift'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.play_circle_fill, color: Colors.green, size: 20),
                        const SizedBox(width: 6),
                        const Text('Active Shift', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Cashier: ${open.cashierName.isEmpty ? "-" : open.cashierName}', style: const TextStyle(fontSize: 13)),
                    Text('Started: ${_dateFmt.format(open.startTime)}', style: const TextStyle(fontSize: 13)),
                    Text('Starting Cash: ${_currency.format(open.startingCash)}', style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    const Text('Sales so far:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navy)),
                    ...DbService.salesDuringShift(open).entries.map((e) => _summaryRow(paymentMethodLabel(e.key), e.value)),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _navy),
                      onPressed: () => _endShift(open),
                      child: const Text('End Shift & Settlement'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text('Shift History', style: TextStyle(fontWeight: FontWeight.bold, color: _navy)),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const Text('No completed shifts yet.', style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            ...history.map((s) {
              final expected = DbService.expectedCashForShift(s);
              final diff = (s.endingCashCounted ?? 0) - expected;
              return ListTile(
                dense: true,
                onTap: () => _viewShiftDetail(s),
                title: Text('${s.cashierName.isEmpty ? "Cashier" : s.cashierName} • ${_dateFmt.format(s.startTime)}'),
                subtitle: Text(diff == 0 ? 'Spot on' : (diff > 0 ? 'Over ${_currency.format(diff)}' : 'Short ${_currency.format(diff.abs())}')),
                trailing: Icon(Icons.circle, size: 10, color: diff == 0 ? Colors.green : (diff > 0 ? Colors.blue : Colors.red)),
              );
            }),
        ],
      ),
    );
  }
}
