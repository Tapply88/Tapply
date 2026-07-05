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
    case 'gofood':
      return 'GoFood';
    case 'grabfood':
      return 'GrabFood';
    case 'shopeefood':
      return 'ShopeeFood';
    case 'bank_transfer':
      return 'Bank Transfer';
    default:
      if (code.startsWith('other_')) return code.substring(6);
      return code;
  }
}

/// Receipt widget reused on: post-payment screen & transaction history.
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

    final isVoided = tx.status == 'void';
    final isClosed = tx.paymentMethod != 'unpaid';

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
        const SizedBox(height: 10),
        if (tx.queueCode != null && tx.queueCode!.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  const Text('QUEUE NUMBER', style: TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1)),
                  Text(tx.queueCode!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: navyColor)),
                ],
              ),
            ),
          ),
        Center(
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isVoided ? Colors.grey.shade300 : (isClosed ? Colors.green.shade50 : Colors.orange.shade50),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isVoided ? Colors.grey.shade600 : (isClosed ? Colors.green : Colors.orange)),
            ),
            child: Text(
              isVoided ? 'VOIDED' : (isClosed ? 'PAID — BILL CLOSED' : 'CHECK — UNPAID'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: isVoided ? Colors.grey.shade800 : (isClosed ? Colors.green.shade800 : Colors.orange.shade800),
              ),
            ),
          ),
        ),
        const Divider(height: 24),
        if (tx.receiptNumber != null)
          Text('Receipt No.: ${tx.receiptNumber}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text('Order ID: ${tx.id.substring(0, tx.id.length >= 8 ? 8 : tx.id.length).toUpperCase()}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(DateFormat('dd MMM yyyy, HH:mm').format(tx.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(tx.salesType, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        if (customerName != null)
          Text('Customer: $customerName', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        if (tx.cashierName != null && tx.cashierName!.isNotEmpty)
          Text('Served by: ${tx.cashierName}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
        if (DbService.showZeroAmountRows || tx.taxAmount != 0) _row(currency, 'Tax', tx.taxAmount),
        if (DbService.showZeroAmountRows || tx.serviceAmount != 0) _row(currency, 'Service', tx.serviceAmount),
        if (tx.discountAmount > 0)
          _row(
            currency,
            (tx.discountLabel != null && tx.discountLabel!.isNotEmpty) ? 'Discount (${tx.discountLabel})' : 'Discount',
            -tx.discountAmount,
          ),
        if (DbService.showZeroAmountRows || tx.roundingAdjustment != 0) _row(currency, 'Rounding', tx.roundingAdjustment),
        const Divider(height: 20),
        _row(currency, 'Total', tx.total, bold: true),
        const SizedBox(height: 10),
        // Payment method + cash tendered/change go right below the total.
        _row(currency, 'Payment', 0, textValue: paymentMethodLabel(tx.paymentMethod)),
        if (tx.paymentMethod == 'cash' && tx.cashReceived != null) ...[
          _row(currency, 'Cash Received', tx.cashReceived!),
          if (tx.changeAmount != null && tx.changeAmount! > 0) _row(currency, 'Change', tx.changeAmount!),
        ],
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

  Widget _row(NumberFormat currency, String label, int amount, {bool bold = false, String? textValue}) {
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
          Text(textValue ?? currency.format(amount), style: style),
        ],
      ),
    );
  }
}
