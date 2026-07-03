import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/db_service.dart';

const navyColor = Color(0xFF092762);

String paymentMethodLabel(String code) {
  switch (code) {
    case 'cash':
      return 'Cash';
    case 'qris_manual':
      return 'QRIS (Manual)';
    case 'qris_midtrans':
      return 'QRIS / E-Wallet (Midtrans)';
    case 'edc_BCA':
      return 'EDC BCA';
    case 'edc_Mandiri':
      return 'EDC Mandiri';
    case 'edc_BNI':
      return 'EDC BNI';
    default:
      return code;
  }
}

/// Widget struk yang dipakai ulang di: halaman setelah bayar & history transaksi.
class ReceiptView extends StatelessWidget {
  final TransactionRecord tx;
  const ReceiptView({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    String? customerName;
    if (tx.memberId != null) {
      final m = DbService.members.get(tx.memberId);
      if (m != null) customerName = '${m.name} (member)';
    } else if (tx.guestName != null && tx.guestName!.isNotEmpty) {
      customerName = tx.guestName;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Column(
            children: [
              if (DbService.businessLogoBase64 != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                    height: 56,
                    child: Image.memory(base64Decode(DbService.businessLogoBase64!), fit: BoxFit.contain),
                  ),
                ),
              Text(DbService.businessName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: navyColor)),
              if (DbService.businessAddress.isNotEmpty)
                Text(DbService.businessAddress, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (DbService.businessPhone.isNotEmpty)
                Text(DbService.businessPhone, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        const Divider(height: 24),
        Text(DateFormat('dd MMM yyyy, HH:mm').format(tx.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(tx.salesType, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        if (customerName != null)
          Text('Pelanggan: $customerName', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text('Bayar: ${paymentMethodLabel(tx.paymentMethod)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        ...tx.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item.productName} x${item.qty}', style: const TextStyle(fontSize: 13)),
                        if (item.note != null && item.note!.isNotEmpty)
                          Text(item.note!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Text(currency.format(item.subtotal), style: const TextStyle(fontSize: 13)),
                ],
              ),
            )),
        const Divider(height: 20),
        _row(currency, 'Sub-Total', tx.itemsSubtotal),
        _row(currency, 'Tax', tx.taxAmount),
        _row(currency, 'Service', tx.serviceAmount),
        if (tx.discountAmount > 0)
          _row(
            currency,
            (tx.discountLabel != null && tx.discountLabel!.isNotEmpty) ? 'Discount (${tx.discountLabel})' : 'Discount',
            -tx.discountAmount,
          ),
        _row(currency, 'Rounding', tx.roundingAdjustment),
        const Divider(height: 20),
        _row(currency, 'Total', tx.total, bold: true),
        const SizedBox(height: 20),
        Center(child: Text(DbService.receiptFooterText, style: const TextStyle(fontSize: 12, color: Colors.grey))),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              const Text('powered by', style: TextStyle(fontSize: 9, color: Colors.grey)),
              const SizedBox(height: 2),
              Image.asset('assets/logo.png', height: 20),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(NumberFormat currency, String label, int amount, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: navyColor,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(currency.format(amount), style: style),
        ],
      ),
    );
  }
}
