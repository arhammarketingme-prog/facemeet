// supabase/functions/create-razorpay-order/index.ts
//
// Creates a Razorpay order for funding an ad campaign's budget.
// RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET live only as Edge
// Function secrets — the key SECRET never reaches the browser.
// (The key ID alone is safe client-side — that's how Razorpay
// Checkout works — but we still create the order here so the
// amount can't be tampered with client-side either.)
//
// Deploy:
//   supabase functions deploy create-razorpay-order
//   supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxx RAZORPAY_KEY_SECRET=xxx

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const keyId = Deno.env.get("RAZORPAY_KEY_ID");
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!keyId || !keySecret) {
      return new Response(JSON.stringify({ error: "payments_not_configured" }), {
        status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const { campaignId, amountInr } = await req.json();
    if (!campaignId || !amountInr || amountInr < 1) {
      return new Response(JSON.stringify({ error: "invalid_request" }), {
        status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const auth = btoa(`${keyId}:${keySecret}`);
    const orderRes = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: { "Authorization": `Basic ${auth}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        amount: Math.round(amountInr * 100), // paise
        currency: "INR",
        notes: { campaignId },
      }),
    });

    if (!orderRes.ok) {
      const detail = await orderRes.text();
      console.error("Razorpay order error:", detail);
      return new Response(JSON.stringify({ error: "order_failed" }), {
        status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const order = await orderRes.json();

    // record a 'created' payment row via the service role, so the
    // amount is pinned server-side before checkout even opens
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (supabaseUrl && serviceKey) {
      await fetch(`${supabaseUrl}/rest/v1/ad_payments`, {
        method: "POST",
        headers: {
          "apikey": serviceKey,
          "Authorization": `Bearer ${serviceKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          campaign_id: campaignId,
          amount_inr: amountInr,
          razorpay_order_id: order.id,
          status: "created",
        }),
      });
    }

    return new Response(
      JSON.stringify({ orderId: order.id, amount: order.amount, currency: order.currency, keyId }),
      { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("create-razorpay-order error:", err);
    return new Response(JSON.stringify({ error: "server_error" }), {
      status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
