// Backend proxy kecil buat Tapply — nyimpen Midtrans Server Key dengan aman.
// Jalankan: cd server && npm install && node index.js
// Deploy ke Railway/Render/Fly.io/VPS. JANGAN commit .env ke git.

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const midtransClient = require('midtrans-client');
const { createClient } = require('@supabase/supabase-js');

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

// Service Role Key -> akses penuh ke Supabase, TAPI cuma dipegang server ini,
// gak pernah dikirim ke app Flutter. Itu yang bikin app bisa "nulis" data
// biar aman walau app-nya sendiri gak login ke Supabase.
const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const snap = new midtransClient.Snap({
  isProduction: false, // ganti true kalau sudah live
  serverKey: process.env.MIDTRANS_SERVER_KEY,
  clientKey: process.env.MIDTRANS_CLIENT_KEY,
});

app.post('/create-transaction', async (req, res) => {
  try {
    const { order_id, gross_amount, customer_name } = req.body;
    const parameter = {
      transaction_details: {
        order_id,
        gross_amount,
      },
      customer_details: {
        first_name: customer_name || 'Pelanggan',
      },
      enabled_payments: ['gopay', 'qris', 'other_qris', 'bank_transfer'],
    };
    const transaction = await snap.createTransaction(parameter);
    res.json(transaction); // berisi token & redirect_url
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/status/:orderId', async (req, res) => {
  try {
    const apiClient = new midtransClient.CoreApi({
      isProduction: false,
      serverKey: process.env.MIDTRANS_SERVER_KEY,
      clientKey: process.env.MIDTRANS_CLIENT_KEY,
    });
    const status = await apiClient.transaction.status(req.params.orderId);
    res.json(status);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// Webhook notifikasi dari Midtrans (set URL ini di dashboard Midtrans)
app.post('/midtrans-webhook', async (req, res) => {
  console.log('Notifikasi Midtrans masuk:', req.body);
  // TODO: update status transaksi di database kamu berdasarkan req.body
  res.sendStatus(200);
});

// ---- Sinkronisasi transaksi dari app kasir (Flutter) ke dashboard web ----
// App Flutter kirim: header 'x-api-key' (dari Setelan > Sinkronisasi di dashboard)
// + body JSON transaksi. Server ini yang cari tau business_id-nya, terus nulis
// ke Supabase pakai Service Role Key (bukan app-nya langsung).
app.post('/sync/transaction', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) {
      return res.status(401).json({ error: 'x-api-key header kosong' });
    }

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();

    if (businessError || !business) {
      return res.status(401).json({ error: 'API key gak valid' });
    }

    const tx = req.body;
    const { error: insertError } = await supabaseAdmin.from('transactions').insert({
      business_id: business.id,
      items: tx.items,
      total: tx.total,
      tax_amount: tx.taxAmount,
      service_amount: tx.serviceAmount,
      discount_amount: tx.discountAmount,
      discount_label: tx.discountLabel,
      rounding_adjustment: tx.roundingAdjustment,
      payment_method: tx.paymentMethod,
      sales_type: tx.salesType,
      guest_name: tx.guestName,
      cashier_name: tx.cashierName,
      cashier_email: tx.cashierEmail,
      receipt_number: tx.receiptNumber,
      queue_code: tx.queueCode,
      status: tx.status,
      created_at: tx.createdAt,
    });

    if (insertError) {
      console.error(insertError);
      return res.status(500).json({ error: 'Gagal simpan ke database' });
    }

    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Tapply backend jalan di port ${PORT}`));
