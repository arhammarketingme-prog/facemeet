// supabase/functions/youtube-search/index.ts
//
// Server-side proxy for the YouTube Data API v3 "search" endpoint.
// The YOUTUBE_API_KEY lives only here (as a Supabase Edge Function
// secret) — it is never sent to, or readable by, the browser.
//
// Deploy:
//   supabase functions deploy youtube-search
//   supabase secrets set YOUTUBE_API_KEY=your_key_here
//
// Invoke from the frontend with:
//   sb.functions.invoke('youtube-search', { body: { query, type } })

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const apiKey = Deno.env.get("YOUTUBE_API_KEY");
    if (!apiKey) {
      // Graceful fallback per spec §14/§25/§45 — never break the app
      // just because an external key hasn't been configured yet.
      return new Response(
        JSON.stringify({ error: "youtube_not_configured", items: [] }),
        { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    const { query, type = "video", pageToken } = await req.json();
    if (!query || typeof query !== "string" || !query.trim()) {
      return new Response(JSON.stringify({ error: "missing_query", items: [] }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const safeType = type === "channel" ? "channel" : "video";
    const params = new URLSearchParams({
      part: "snippet",
      q: query.trim(),
      type: safeType,
      maxResults: "12",
      safeSearch: "moderate",
      key: apiKey,
    });
    if (pageToken) params.set("pageToken", pageToken);

    const ytRes = await fetch(`https://www.googleapis.com/youtube/v3/search?${params.toString()}`);

    if (!ytRes.ok) {
      // Quota exceeded, invalid key, etc. — surface a clean fallback
      // state instead of a raw error the frontend can't render.
      const detail = await ytRes.text();
      console.error("YouTube API error:", ytRes.status, detail);
      return new Response(
        JSON.stringify({ error: "youtube_unavailable", items: [] }),
        { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    const data = await ytRes.json();
    const items = (data.items || []).map((it: any) => ({
      kind: safeType,
      videoId: it.id?.videoId || null,
      channelId: it.id?.channelId || it.snippet?.channelId || null,
      title: it.snippet?.title || "",
      description: it.snippet?.description || "",
      channelTitle: it.snippet?.channelTitle || "",
      publishedAt: it.snippet?.publishedAt || null,
      thumbnail: it.snippet?.thumbnails?.medium?.url || it.snippet?.thumbnails?.default?.url || null,
    }));

    return new Response(
      JSON.stringify({ items, nextPageToken: data.nextPageToken || null }),
      { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("youtube-search function error:", err);
    return new Response(JSON.stringify({ error: "server_error", items: [] }), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
