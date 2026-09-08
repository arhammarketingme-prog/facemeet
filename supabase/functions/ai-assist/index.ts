// supabase/functions/ai-assist/index.ts
//
// Server-side proxy to the Anthropic API for post-writing help
// and translation. ANTHROPIC_API_KEY lives only as an Edge
// Function secret — never sent to the browser. This is a
// SEPARATE key from Claude.ai; get one at console.anthropic.com
// (a paid API account, distinct from a Claude.ai subscription).
//
// Deploy:
//   supabase functions deploy ai-assist
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-xxx

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const PROMPTS: Record<string, (text: string, lang?: string) => string> = {
  improve: (text) => `Improve this social media post for clarity and engagement. Keep the same meaning and length roughly the same. Return ONLY the improved post text, nothing else.\n\nPost: ${text}`,
  expand: (text) => `Expand this short idea into a fuller social media post (2-4 sentences). Return ONLY the post text, nothing else.\n\nIdea: ${text}`,
  translate: (text, lang) => `Translate this social media post into ${lang === 'mr' ? 'Marathi' : lang === 'hi' ? 'Hindi' : 'English'}. Return ONLY the translated text, nothing else.\n\nPost: ${text}`,
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "ai_not_configured" }), {
        status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const { action, text, lang } = await req.json();
    if (!action || !PROMPTS[action] || !text || !text.trim()) {
      return new Response(JSON.stringify({ error: "invalid_request" }), {
        status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }
    if (text.length > 2000) {
      return new Response(JSON.stringify({ error: "text_too_long" }), {
        status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 400,
        messages: [{ role: "user", content: PROMPTS[action](text, lang) }],
      }),
    });

    if (!res.ok) {
      const detail = await res.text();
      console.error("Anthropic API error:", detail);
      return new Response(JSON.stringify({ error: "ai_unavailable" }), {
        status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const data = await res.json();
    const resultText = (data.content || []).map((b: any) => b.text || "").join("").trim();

    return new Response(JSON.stringify({ result: resultText }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("ai-assist error:", err);
    return new Response(JSON.stringify({ error: "server_error" }), {
      status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
