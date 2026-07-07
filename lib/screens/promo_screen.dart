import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/promo.dart';
import '../services/db_service.dart';

const _navy = Color(0xFF623609);

class PromoScreen extends StatefulWidget {
  const PromoScreen({super.key});

  @override
  State<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends State<PromoScreen> {
  final _uuid = const Uuid();
  final _dateFmt = DateFormat('dd MMM yyyy');
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  Future<void> _editPromo({Promo? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final valueCtrl = TextEditingController(text: existing != null ? existing.value.toStringAsFixed(existing.discountType == 'percentage' ? 1 : 0) : '');
    final minPurchaseCtrl = TextEditingController(text: '${existing?.minPurchase ?? 0}');
    String discountType = existing?.discountType ?? 'percentage';
    String scope = existing?.scope ?? 'cart';
    final selectedProductIds = <String>{...(existing?.productIds ?? [])};
    DateTime? startDate = existing?.startDate;
    DateTime? endDate = existing?.endDate;
    bool active = existing?.active ?? true;
    String triggerType = existing?.triggerType ?? 'always';
    String? triggerMonthDay = existing?.triggerMonthDay;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(existing == null ? 'New Promo' : 'Edit Promo', style: const TextStyle(color: _navy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Promo name', hintText: 'mis. Promo Ramadan')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Persen (%)', style: TextStyle(fontSize: 13)),
                          value: 'percentage',
                          groupValue: discountType,
                          onChanged: (v) => setDialogState(() => discountType = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Nominal (Rp)', style: TextStyle(fontSize: 13)),
                          value: 'fixed',
                          groupValue: discountType,
                          onChanged: (v) => setDialogState(() => discountType = v!),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: valueCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: discountType == 'percentage' ? 'Discount amount (%)' : 'Discount amount (Rp)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: minPurchaseCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minimum pembelian (Rp, 0 = tanpa minimum)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) setDialogState(() => startDate = picked);
                          },
                          child: Text(startDate == null ? 'Start date' : _dateFmt.format(startDate!), style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: endDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) setDialogState(() => endDate = picked);
                          },
                          child: Text(endDate == null ? 'End date' : _dateFmt.format(endDate!), style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                  const Text('Leave dates blank to run indefinitely.', style: TextStyle(fontSize: 11, color: const Color(0xFF623609))),
                  const SizedBox(height: 12),
                  const Text('WHEN DOES THIS APPLY', style: TextStyle(fontSize: 11, color: const Color(0xFF623609), fontWeight: FontWeight.bold)),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Always (within the date range above)', style: TextStyle(fontSize: 13)),
                    value: 'always',
                    groupValue: triggerType,
                    onChanged: (v) => setDialogState(() => triggerType = v!),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Only on the member's birthday", style: TextStyle(fontSize: 13)),
                    subtitle: const Text('A member must be selected at checkout, and their birthday must be on file.', style: TextStyle(fontSize: 11)),
                    value: 'birthday',
                    groupValue: triggerType,
                    onChanged: (v) => setDialogState(() => triggerType = v!),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Only on a specific date every year', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('e.g. store anniversary — repeats annually, year is ignored.', style: TextStyle(fontSize: 11)),
                    value: 'specific_date',
                    groupValue: triggerType,
                    onChanged: (v) => setDialogState(() => triggerType = v!),
                  ),
                  if (triggerType == 'specific_date')
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 8),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: _navy), foregroundColor: _navy),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => triggerMonthDay = '${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
                          }
                        },
                        child: Text(
                          triggerMonthDay == null ? 'Pick date (day & month)' : 'Every ${triggerMonthDay!.split('-')[1]}/${triggerMonthDay!.split('-')[0]}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text('APPLIES TO', style: TextStyle(fontSize: 11, color: const Color(0xFF623609), fontWeight: FontWeight.bold)),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Entire Receipt', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Discount calculated from total spend', style: TextStyle(fontSize: 11)),
                    value: 'cart',
                    groupValue: scope,
                    onChanged: (v) => setDialogState(() => scope = v!),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Specific Products (preset)', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Automatically applied when checked products are in the cart', style: TextStyle(fontSize: 11)),
                    value: 'product',
                    groupValue: scope,
                    onChanged: (v) => setDialogState(() => scope = v!),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Per Item (optional at checkout)', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Cashier checks it manually per product when adding to cart, e.g. discount for bringing your own tumbler', style: TextStyle(fontSize: 11)),
                    value: 'item',
                    groupValue: scope,
                    onChanged: (v) => setDialogState(() => scope = v!),
                  ),
                  if (scope == 'product' || scope == 'item') ...[
                    const SizedBox(height: 4),
                    Text(
                      scope == 'item' ? 'Limit to specific products (optional, leave blank = applies to all products):' : 'Select products:',
                      style: const TextStyle(fontSize: 11, color: const Color(0xFF623609), fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFF623609)), borderRadius: BorderRadius.circular(8)),
                      child: ListView(
                        shrinkWrap: true,
                        children: DbService.products.values.map((p) {
                          final checked = selectedProductIds.contains(p.id);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            activeColor: _navy,
                            title: Text(p.name, style: const TextStyle(fontSize: 13)),
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selectedProductIds.add(p.id);
                              } else {
                                selectedProductIds.remove(p.id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                    if (scope == 'product' && selectedProductIds.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Select at least 1 product.', style: TextStyle(fontSize: 11, color: Colors.red)),
                      ),
                  ],
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: _navy,
                    title: const Text('Active'),
                    value: active,
                    onChanged: (v) => setDialogState(() => active = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _navy),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  if (scope == 'product' && selectedProductIds.isEmpty) return;
                  final promo = Promo(
                    id: existing?.id ?? _uuid.v4(),
                    name: nameCtrl.text.trim(),
                    discountType: discountType,
                    value: double.tryParse(valueCtrl.text) ?? 0,
                    startDate: startDate,
                    endDate: endDate,
                    minPurchase: int.tryParse(minPurchaseCtrl.text) ?? 0,
                    active: active,
                    scope: scope,
                    productIds: selectedProductIds.toList(),
                    triggerType: triggerType,
                    triggerMonthDay: triggerType == 'specific_date' ? triggerMonthDay : null,
                  );
                  await DbService.savePromo(promo);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deletePromo(Promo p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Promo?'),
        content: Text('Are you sure you want to delete "${p.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await DbService.deletePromo(p.id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final promos = DbService.promos.values.toList()
      ..sort((a, b) => b.active == a.active ? 0 : (b.active ? 1 : -1));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Promo'),
        actions: [IconButton(onPressed: () => _editPromo(), icon: const Icon(Icons.add))],
      ),
      body: promos.isEmpty
          ? const Center(child: Text('No promos yet. Tap + to create one.', style: TextStyle(color: const Color(0xFF623609))))
          : ListView.builder(
              itemCount: promos.length,
              itemBuilder: (ctx, i) {
                final p = promos[i];
                final valueLabel = p.discountType == 'percentage' ? '${p.value.toStringAsFixed(0)}%' : _currency.format(p.value.round());
                final dateLabel = (p.startDate != null || p.endDate != null)
                    ? '${p.startDate != null ? _dateFmt.format(p.startDate!) : 'kapan aja'} — ${p.endDate != null ? _dateFmt.format(p.endDate!) : 'seterusnya'}'
                    : 'Runs indefinitely';
                return ListTile(
                  leading: Icon(Icons.local_offer, color: p.active ? _navy : const Color(0xFF623609)),
                  title: Text(p.name, style: TextStyle(color: p.active ? _navy : const Color(0xFF623609), fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Discount $valueLabel${p.minPurchase > 0 ? ' • min. ${_currency.format(p.minPurchase)}' : ''}'
                    '${p.scope == 'product' ? ' • ${p.productIds.length} products (preset)' : p.scope == 'item' ? ' • per item${p.productIds.isNotEmpty ? ' (${p.productIds.length} products)' : ' (all products)'}' : ' • entire receipt'}'
                    '${p.triggerType == 'birthday' ? ' • 🎂 birthday only' : p.triggerType == 'specific_date' ? ' • 📅 ${p.triggerMonthDay ?? ''} only' : ''}\n$dateLabel',
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!p.active) const Text('Inactive', style: TextStyle(fontSize: 10, color: const Color(0xFF623609))),
                      IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editPromo(existing: p)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => _deletePromo(p)),
                    ],
                  ),
                  onTap: () => _editPromo(existing: p),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _navy,
        onPressed: () => _editPromo(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
