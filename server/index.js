// Backend proxy kecil buat Tapply — nyimpen Midtrans Server Key dengan aman.
// Jalankan: cd server && npm install && node index.js
// Deploy ke Railway/Render/Fly.io/VPS. JANGAN commit .env ke git.

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const midtransClient = require('midtrans-client');
const { createClient } = require('@supabase/supabase-js');
const fetch = require('node-fetch');

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
    const { error: insertError } = await supabaseAdmin.from('transactions').upsert({
      id: tx.id,
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

// ---- Sinkronisasi member (upsert berdasarkan id lokal dari app) ----
app.post('/sync/member', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const m = req.body;
    const { error: upsertError } = await supabaseAdmin.from('members').upsert({
      id: m.id,
      business_id: business.id,
      name: m.name,
      phone: m.phone,
      points: m.points,
      birth_date: m.birthDate ? m.birthDate.substring(0, 10) : null,
      email: m.email || null,
    });

    if (upsertError) {
      console.error(upsertError);
      return res.status(500).json({ error: 'Gagal simpan member' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Sinkronisasi promo (upsert berdasarkan id lokal dari app) ----
app.post('/sync/promo', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const p = req.body;
    const { error: upsertError } = await supabaseAdmin.from('promos').upsert({
      id: p.id,
      business_id: business.id,
      name: p.name,
      discount_type: p.discountType,
      value: p.value,
      scope: p.scope,
      product_ids: p.productIds ?? [],
      start_date: p.startDate ? p.startDate.substring(0, 10) : null,
      end_date: p.endDate ? p.endDate.substring(0, 10) : null,
      min_purchase: p.minPurchase,
      active: p.active,
      trigger_type: p.triggerType ?? 'always',
      trigger_month_day: p.triggerMonthDay ?? null,
    });

    if (upsertError) {
      console.error(upsertError);
      return res.status(500).json({ error: 'Gagal simpan promo' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Sinkronisasi produk (upsert berdasarkan id lokal dari app) ----
// Foto produk sengaja gak dikirim di sini (base64 kebesaran) — cuma data teks.
app.post('/sync/product', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const p = req.body;
    const { error: upsertError } = await supabaseAdmin.from('products').upsert({
      id: p.id,
      business_id: business.id,
      name: p.name,
      price: p.price,
      category: p.category,
      stock: p.stock,
      sort_order: p.sortOrder,
      is_active: p.isActive,
      sku: p.sku,
      volume: p.volume,
      label_size: p.labelSize,
      show_price_on_label: p.showPriceOnLabel,
      label_variant: p.labelVariant,
      label_addons: p.labelAddons || [],
      expiry_date: p.expiryDate ? p.expiryDate.substring(0, 10) : null,
      production_date: p.productionDate ? p.productionDate.substring(0, 10) : null,
      online_price: p.onlinePrice,
    });

    if (upsertError) {
      console.error(upsertError);
      return res.status(500).json({ error: 'Gagal simpan produk' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Sinkronisasi shift (upsert berdasarkan id lokal dari app) ----
app.post('/sync/shift', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const s = req.body;
    const { error: upsertError } = await supabaseAdmin.from('shifts').upsert({
      id: s.id,
      business_id: business.id,
      cashier_name: s.cashierName,
      cashier_email: s.cashierEmail,
      start_time: s.startTime,
      starting_cash: s.startingCash,
      end_time: s.endTime,
      ending_cash_counted: s.endingCashCounted,
      status: s.status,
      note: s.note,
    });

    if (upsertError) {
      console.error(upsertError);
      return res.status(500).json({ error: 'Gagal simpan shift' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Tarik data dari cloud ke app (bagian dari sync dua arah) ----
// App manggil ini pas cashier klik "Tarik Data dari Dashboard" di Setelan.
app.get('/sync/pull', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: businessFull, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('*')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !businessFull) return res.status(401).json({ error: 'API key gak valid' });
    const business = businessFull;

    const [{ data: products }, { data: members }, { data: promos }, { data: variations }, { data: addons }, { data: staff }, { data: ingredients }, { data: recipeItems }, { data: tables }] = await Promise.all([
      supabaseAdmin.from('products').select('*').eq('business_id', business.id),
      supabaseAdmin.from('members').select('*').eq('business_id', business.id),
      supabaseAdmin.from('promos').select('*').eq('business_id', business.id),
      supabaseAdmin.from('variations').select('*').eq('business_id', business.id),
      supabaseAdmin.from('addons').select('*').eq('business_id', business.id),
      supabaseAdmin.from('staff').select('*').eq('business_id', business.id).eq('active', true),
      supabaseAdmin.from('ingredients').select('*').eq('business_id', business.id),
      supabaseAdmin.from('recipe_items').select('*').eq('business_id', business.id),
        supabaseAdmin.from('dining_tables').select('*').eq('business_id', business.id),
    ]);

    res.json({
      tables: (tables || []).map((t) => ({
        id: t.id,
        name: t.name,
        sortOrder: t.sort_order,
      })),
      products: (products || []).map((p) => ({
        id: p.id,
        name: p.name,
        price: p.price,
        category: p.category,
        stock: p.stock,
        sortOrder: p.sort_order,
        isActive: p.is_active,
        sku: p.sku,
        volume: p.volume,
        labelSize: p.label_size,
        showPriceOnLabel: p.show_price_on_label,
        labelVariant: p.label_variant,
        labelAddons: p.label_addons || [],
        expiryDate: p.expiry_date,
        productionDate: p.production_date,
        imageBase64: p.image_base64,
        onlinePrice: p.online_price,
      })),
      members: (members || []).map((m) => ({
        id: m.id,
        name: m.name,
        phone: m.phone,
        points: m.points,
        birthDate: m.birth_date,
      })),
      promos: (promos || []).map((p) => ({
        id: p.id,
        name: p.name,
        discountType: p.discount_type,
        value: p.value,
        scope: p.scope,
        productIds: p.product_ids || [],
        startDate: p.start_date,
        endDate: p.end_date,
        minPurchase: p.min_purchase,
        active: p.active,
        triggerType: p.trigger_type,
        triggerMonthDay: p.trigger_month_day,
      })),
      variations: (variations || []).map((v) => ({
        id: v.id,
        name: v.name,
        sortOrder: v.sort_order,
        price: v.price,
        onlinePrice: v.online_price,
      })),
      addons: (addons || []).map((a) => ({
        id: a.id,
        name: a.name,
        price: a.price,
        sortOrder: a.sort_order,
        onlinePrice: a.online_price,
      })),
      staff: (staff || []).map((s) => ({
        id: s.id,
        name: s.name,
        role: s.role,
        pin: s.pin,
      })),
      ingredients: (ingredients || []).map((i) => ({
        id: i.id,
        name: i.name,
        unit: i.unit,
        stock: i.stock,
        lowStockThreshold: i.low_stock_threshold,
      })),
      recipeItems: (recipeItems || []).map((r) => ({
        id: r.id,
        productId: r.product_id,
        ingredientId: r.ingredient_id,
        quantity: r.quantity,
      })),
      business: {
        name: business.name,
        address: business.address,
        phone: business.phone,
        footerText: business.footer_text,
        taxPercent: business.tax_percent,
        servicePercent: business.service_percent,
        discountPercent: business.discount_percent,
        roundingEnabled: business.rounding_enabled,
        roundingNearest: business.rounding_nearest,
        managerPin: business.manager_pin,
        pinRequiredForCancel: business.pin_required_for_cancel,
        printCheckEnabled: business.print_check_enabled,
        queueNumberEnabled: business.queue_number_enabled,
        queueStartNumber: business.queue_start_number,
        pointsRedemptionValue: business.points_redemption_value,
        pointsRedemptionMultiple: business.points_redemption_multiple,
        pointsEarnRate: business.points_earn_rate,
        plan: business.plan,
        planExpiresAt: business.plan_expires_at,
        logoBase64: business.logo_base64,
      },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Deduct ingredient stock (dipanggil app pas transaksi produk yang punya resep) ----
app.post('/sync/ingredient-deduct', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });
    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const deductions = req.body.deductions || []; // [{ ingredientId, amount }]
    for (const d of deductions) {
      const { data: ing } = await supabaseAdmin
        .from('ingredients')
        .select('stock')
        .eq('id', d.ingredientId)
        .eq('business_id', business.id)
        .single();
      if (ing) {
        const newStock = (ing.stock || 0) - (d.amount || 0);
        await supabaseAdmin.from('ingredients').update({ stock: newStock }).eq('id', d.ingredientId);
      }
    }
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Kirim struk via WhatsApp (Fonnte) ----
// Satu akun Fonnte dipakai bersama buat semua bisnis (shared gateway Tapply).
app.post('/send/whatsapp', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const { phone, message } = req.body;
    if (!phone || !message) return res.status(400).json({ error: 'phone dan message wajib diisi' });

    const fonnteRes = await fetch('https://api.fonnte.com/send', {
      method: 'POST',
      headers: {
        'Authorization': process.env.FONNTE_TOKEN,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ target: phone, message }),
    });
    const fonnteData = await fonnteRes.json();
    if (fonnteData.status === false || fonnteData.status === 'false') {
      return res.status(500).json({ error: 'Gagal kirim WhatsApp', detail: fonnteData });
    }
    res.json({ success: true, detail: fonnteData });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Kirim struk via Email (Resend) ----
app.post('/send/email', async (req, res) => {
  try {
    const apiKey = req.headers['x-api-key'];
    if (!apiKey) return res.status(401).json({ error: 'x-api-key header kosong' });

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id')
      .eq('sync_api_key', apiKey)
      .single();
    if (businessError || !business) return res.status(401).json({ error: 'API key gak valid' });

    const { to, subject, text } = req.body;
    if (!to || !subject || !text) return res.status(400).json({ error: 'to, subject, text wajib diisi' });

    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: process.env.RESEND_FROM || 'Tapply <onboarding@resend.dev>',
        to: [to],
        subject,
        text,
      }),
    });
    const resendData = await resendRes.json();
    if (!resendRes.ok) {
      return res.status(500).json({ error: 'Gagal kirim email', detail: resendData });
    }
    res.json({ success: true, detail: resendData });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ---- Login email+password buat app kasir (akun sama kayak dashboard) ----
app.post('/auth/login', async (req, res) => {
  try {
    const { email, password, deviceId, deviceName } = req.body;
    if (!email || !password) return res.status(400).json({ error: 'Email dan password wajib diisi' });

    const { data: authData, error: authError } = await supabaseAdmin.auth.signInWithPassword({ email, password });
    if (authError || !authData.user) {
      console.error('LOGIN GAGAL untuk', email, '- alasan asli:', authError ? authError.message : 'no user returned');
      return res.status(401).json({ error: 'Email atau password salah' });
    }

    const { data: link, error: linkError } = await supabaseAdmin
      .from('business_users')
      .select('business_id')
      .eq('user_id', authData.user.id)
      .single();
    if (linkError || !link) {
      return res.status(404).json({ error: 'Akun ini belum terhubung ke bisnis manapun' });
    }

    const { data: business, error: businessError } = await supabaseAdmin
      .from('businesses')
      .select('id, name, sync_api_key, plan, plan_expires_at')
      .eq('id', link.business_id)
      .single();
    if (businessError || !business) {
      return res.status(404).json({ error: 'Data bisnis tidak ditemukan' });
    }

    // ---- Device gating: Trial/Starter plan cuma boleh 1 device aktif ----
    const isProActive =
      business.plan === 'pro' ||
      business.plan === 'multi_outlet' ||
      (business.plan === 'trial' && business.plan_expires_at && new Date(business.plan_expires_at) > new Date());

    if (deviceId) {
      const { data: existingDevices } = await supabaseAdmin
        .from('devices')
        .select('device_id')
        .eq('business_id', business.id);

      const alreadyRegistered = (existingDevices || []).some((d) => d.device_id === deviceId);

      if (!isProActive && !alreadyRegistered && (existingDevices || []).length >= 1) {
        return res.status(403).json({
          error: 'This plan only allows 1 device. Upgrade to Pro to connect additional devices.',
        });
      }

      await supabaseAdmin.from('devices').upsert(
        {
          business_id: business.id,
          device_id: deviceId,
          device_name: deviceName || null,
          last_seen_at: new Date().toISOString(),
        },
        { onConflict: 'business_id,device_id' }
      );
    }

    res.json({
      businessId: business.id,
      businessName: business.name,
      syncApiKey: business.sync_api_key,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Tapply backend jalan di port ${PORT}`));
