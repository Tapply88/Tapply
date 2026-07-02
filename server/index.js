// Backend proxy kecil buat Tapply — nyimpen Midtrans Server Key dengan aman.
// Jalankan: cd server && npm install && node index.js
// Deploy ke Railway/Render/Fly.io/VPS. JANGAN commit .env ke git.

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const midtransClient = require('midtrans-client');

const app = express();
app.use(cors());
app.use(express.json());

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

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Tapply backend jalan di port ${PORT}`));
