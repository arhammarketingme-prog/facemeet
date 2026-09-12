// supabase/functions/send-notification-email/index.ts
//
// Sends an email for a notification, via Resend (resend.com — a
// transactional email API with a generous free tier). RESEND_API_KEY
// lives only as an Edge Function secret.
//
// This function does NOT run on its own — nothing calls it
// automatically just by deploying it. Wire it up with a Supabase
// Database Webhook (Dashboard → Database → Webhooks → Create a
// new webhook): table = notifications, event = INSERT, type =
// HTTP request, pick this function as the target. That's a
// dashboard setting, not something expressible in a .sql file,
// which is why it's not in the schema — see README for the exact
// steps.
//
// Deploy:
//   supabase functions deploy send-notification-email
//   supabase secrets set RESEND_API_KEY=re_xxx RESEND_FROM="Vartex <notifications@yourdomain.com>"

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const LABELS: Record<string, string> = {
  follow: "started following you",
  like: "liked your post",
  comment: "commented on your post",
  community_join: "joined your community",
  poll_vote: "voted on your poll",
  message: "sent you a message",
  mention: "mentioned you",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const resendKey = Deno.env.get("RESEND_API_KEY");
    const fromAddress = Deno.env.get("RESEND_FROM");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!resendKey || !fromAddress || !supabaseUrl || !serviceKey) {
      return new Response(JSON.stringify({ error: "email_not_configured" }), {
        status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    // Database Webhooks POST the row as { type, table, record, ... }
    const payload = await req.json();
    const notification = payload.record;
    if (!notification) {
      return new Response(JSON.stringify({ error: "no_record" }), {
        status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    // look up the recipient's email (auth.users) and their notification preference
    const restHeaders = { "apikey": serviceKey, "Authorization": `Bearer ${serviceKey}` };
    const profileRes = await fetch(`${supabaseUrl}/rest/v1/profiles?id=eq.${notification.user_id}&select=email_notifications,username`, { headers: restHeaders });
    const profiles = await profileRes.json();
    const profile = profiles?.[0];
    if (!profile || profile.email_notifications === false) {
      return new Response(JSON.stringify({ skipped: "opted_out_or_missing" }), {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const userRes = await fetch(`${supabaseUrl}/auth/v1/admin/users/${notification.user_id}`, { headers: restHeaders });
    const userData = await userRes.json();
    const toEmail = userData?.email;
    if (!toEmail) {
      return new Response(JSON.stringify({ skipped: "no_email" }), {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const label = LABELS[notification.type] || "sent you a notification";

    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: fromAddress,
        to: toEmail,
        subject: `Vartex — someone ${label}`,
        html: `<p>Hi ${profile.username || ""},</p><p>Someone ${label} on Vartex.</p><p><a href="https://your-site-url/">Open Vartex</a></p><p style="color:#888;font-size:12px">You're getting this because you have email notifications on. Turn them off anytime in Profile settings.</p>`,
      }),
    });

    if (!emailRes.ok) {
      const detail = await emailRes.text();
      console.error("Resend error:", detail);
      return new Response(JSON.stringify({ error: "send_failed" }), {
        status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ sent: true }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("send-notification-email error:", err);
    return new Response(JSON.stringify({ error: "server_error" }), {
      status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
