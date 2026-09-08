// supabase/functions/verify-razorpay-payment/index.ts
//
// Verifies the HMAC signature Razorpay Checkout returns after
// payment, using RAZORPAY_KEY_SECRET (server-side only). Only on
// a valid signature does it mark the payment 'paid' and credit
// the campaign's budget — this is the step that makes the
// payment "real" rather than something the client could fake by
// just calling an insert.
//
// Deploy:
//   supabase functions deploy verify-razorpay-payment
//   supabase secrets set RAZORPAY_KEY_SECRET=xxx
// (SUPABASE_SERVICE_ROLE_KEY and SUPABASE_URL are already
// available to every Edge Function by default in this project.)

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function hmacHex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  return [...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!keySecret || !supabaseUrl || !serviceKey) {
      return new Response(JSON.stringify({ error: "payments_not_configured" }), {
        status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const { razorpay_order_id, razorpay_payment_id, razorpay_signature, campaignId, amountInr } = await req.json();
    if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature || !campaignId) {
      return new Response(JSON.stringify({ error: "invalid_request", verified: false }), {
        status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const expectedSignature = await hmacHex(keySecret, `${razorpay_order_id}|${razorpay_payment_id}`);
    const verified = expectedSignature === razorpay_signature;

    const restHeaders = {
      "apikey": serviceKey,
      "Authorization": `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      "Prefer": "return=minimal",
    };

    if (verified) {
      // mark the payment row paid
      await fetch(`${supabaseUrl}/rest/v1/ad_payments?razorpay_order_id=eq.${razorpay_order_id}`, {
        method: "PATCH",
        headers: restHeaders,
        body: JSON.stringify({ status: "paid", razorpay_payment_id }),
      });

      // credit the campaign's budget and make sure it's active
      const campRes = await fetch(`${supabaseUrl}/rest/v1/ad_campaigns?id=eq.${campaignId}&select=budget_inr`, {
        headers: { "apikey": serviceKey, "Authorization": `Bearer ${serviceKey}` },
      });
      const campData = await campRes.json();
      const currentBudget = campData?.[0]?.budget_inr || 0;

      await fetch(`${supabaseUrl}/rest/v1/ad_campaigns?id=eq.${campaignId}`, {
        method: "PATCH",
        headers: restHeaders,
        body: JSON.stringify({ budget_inr: currentBudget + (amountInr || 0), status: "active" }),
      });
    } else {
      await fetch(`${supabaseUrl}/rest/v1/ad_payments?razorpay_order_id=eq.${razorpay_order_id}`, {
        method: "PATCH",
        headers: restHeaders,
        body: JSON.stringify({ status: "failed" }),
      });
    }

    return new Response(JSON.stringify({ verified }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("verify-razorpay-payment error:", err);
    return new Response(JSON.stringify({ error: "server_error", verified: false }), {
      status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
