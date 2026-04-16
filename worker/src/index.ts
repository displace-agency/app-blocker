import { parseDnsQuery, buildBlockedResponse, isDomainBlocked } from "./dns";

interface Env {
  BLOCKLIST: KVNamespace;
  UPSTREAM_DOH: string;
  API_KEY: string;
}

// In-memory cache to minimize KV reads
let cachedDomains: Set<string> | null = null;
let cachedLocked: boolean = true;
let cacheTime = 0;
const CACHE_TTL = 60_000; // 60 seconds

async function loadBlocklist(env: Env): Promise<{ domains: Set<string>; locked: boolean }> {
  const now = Date.now();
  if (cachedDomains && now - cacheTime < CACHE_TTL) {
    return { domains: cachedDomains, locked: cachedLocked };
  }

  const [domainsRaw, statusRaw] = await Promise.all([
    env.BLOCKLIST.get("domains"),
    env.BLOCKLIST.get("status"),
  ]);

  const domains: string[] = domainsRaw ? JSON.parse(domainsRaw) : [];
  cachedDomains = new Set(domains.map((d) => d.toLowerCase()));

  if (statusRaw) {
    const status = JSON.parse(statusRaw);
    cachedLocked = status.locked !== false;
    // Check if cooldown has expired
    if (status.cooldownEnd && Date.now() > status.cooldownEnd) {
      cachedLocked = true;
    }
  } else {
    cachedLocked = true;
  }

  cacheTime = now;
  return { domains: cachedDomains, locked: cachedLocked };
}

// Invalidate cache after sync
function invalidateCache() {
  cachedDomains = null;
  cacheTime = 0;
}

/** Handle DNS-over-HTTPS queries */
async function handleDnsQuery(request: Request, env: Env): Promise<Response> {
  let queryBuf: ArrayBuffer;

  if (request.method === "GET") {
    // GET /dns-query?dns=<base64url>
    const url = new URL(request.url);
    const dnsParam = url.searchParams.get("dns");
    if (!dnsParam) {
      return new Response("Missing dns parameter", { status: 400 });
    }
    // base64url decode
    const b64 = dnsParam.replace(/-/g, "+").replace(/_/g, "/");
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    queryBuf = bytes.buffer;
  } else if (request.method === "POST") {
    const contentType = request.headers.get("content-type") || "";
    if (!contentType.includes("application/dns-message")) {
      return new Response("Invalid content type", { status: 415 });
    }
    queryBuf = await request.arrayBuffer();
  } else {
    return new Response("Method not allowed", { status: 405 });
  }

  // Parse the DNS query
  const query = parseDnsQuery(queryBuf);
  if (!query) {
    // Can't parse → forward to upstream
    return forwardToUpstream(queryBuf, env);
  }

  // Check blocklist
  const { domains, locked } = await loadBlocklist(env);

  if (locked && isDomainBlocked(query.domain, domains)) {
    // Return 0.0.0.0 response
    const blocked = buildBlockedResponse(query);
    return new Response(blocked, {
      headers: { "content-type": "application/dns-message" },
    });
  }

  // Not blocked → forward to upstream
  return forwardToUpstream(queryBuf, env);
}

/** Forward DNS query to upstream resolver (Cloudflare 1.1.1.1) */
async function forwardToUpstream(queryBuf: ArrayBuffer, env: Env): Promise<Response> {
  const upstream = env.UPSTREAM_DOH || "https://cloudflare-dns.com/dns-query";
  const resp = await fetch(upstream, {
    method: "POST",
    headers: { "content-type": "application/dns-message" },
    body: queryBuf,
  });

  return new Response(resp.body, {
    status: resp.status,
    headers: { "content-type": "application/dns-message" },
  });
}

/** Handle sync API from Mac daemon */
async function handleSync(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as {
    domains?: string[];
    locked?: boolean;
    cooldownEnd?: number | null;
  };

  const writes: Promise<void>[] = [];

  if (body.domains !== undefined) {
    writes.push(env.BLOCKLIST.put("domains", JSON.stringify(body.domains)));
  }

  if (body.locked !== undefined) {
    writes.push(
      env.BLOCKLIST.put(
        "status",
        JSON.stringify({
          locked: body.locked,
          cooldownEnd: body.cooldownEnd || null,
          updatedAt: Date.now(),
        })
      )
    );
  }

  await Promise.all(writes);
  invalidateCache();

  return Response.json({ ok: true });
}

/** Handle status API */
async function handleStatus(env: Env): Promise<Response> {
  const [domainsRaw, statusRaw] = await Promise.all([
    env.BLOCKLIST.get("domains"),
    env.BLOCKLIST.get("status"),
  ]);

  return Response.json({
    domains: domainsRaw ? JSON.parse(domainsRaw) : [],
    status: statusRaw ? JSON.parse(statusRaw) : { locked: true },
  });
}

/** Store a one-time setup code (called by Mac app) */
async function handleStoreCode(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as { code: string; token: string };
  if (!body.code || !body.token) {
    return Response.json({ error: "Missing code or token" }, { status: 400 });
  }

  // Store with 5-minute TTL (in case user never scans)
  await env.BLOCKLIST.put(`setup:${body.token}`, body.code, { expirationTtl: 300 });
  return Response.json({ ok: true });
}

/** Self-destructing setup page -- shows code for 5 seconds, then deletes it */
async function handleSetupPage(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const token = url.searchParams.get("t");

  if (!token) {
    return new Response("Invalid link", { status: 400 });
  }

  // Read and immediately delete the code (one-time use)
  const code = await env.BLOCKLIST.get(`setup:${token}`);
  if (code) {
    await env.BLOCKLIST.delete(`setup:${token}`);
  }

  const html = `<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #0a0a0a;
      color: white;
      font-family: -apple-system, system-ui, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      text-align: center;
    }
    .container { padding: 40px; }
    .code {
      font-size: 72px;
      font-weight: 800;
      letter-spacing: 16px;
      color: #34d399;
      margin: 24px 0;
      font-variant-numeric: tabular-nums;
    }
    .timer {
      font-size: 14px;
      color: #666;
      margin-top: 16px;
    }
    .expired {
      color: #ef4444;
      font-size: 24px;
    }
    .instruction {
      color: #999;
      font-size: 16px;
      max-width: 300px;
      margin: 0 auto;
      line-height: 1.5;
    }
    .bar {
      width: 200px;
      height: 4px;
      background: #222;
      border-radius: 2px;
      margin: 16px auto 0;
      overflow: hidden;
    }
    .bar-fill {
      height: 100%;
      background: #34d399;
      border-radius: 2px;
      animation: shrink 5s linear forwards;
    }
    @keyframes shrink { from { width: 100%; } to { width: 0%; } }
  </style>
</head>
<body>
  <div class="container" id="content">
    ${code ? `
      <p class="instruction">Type this into Screen Time now</p>
      <div class="code" id="code">${code}</div>
      <div class="bar"><div class="bar-fill"></div></div>
      <p class="timer" id="timer">Disappears in 5 seconds</p>
      <script>
        let s = 5;
        const t = setInterval(() => {
          s--;
          if (s <= 0) {
            clearInterval(t);
            document.getElementById('content').innerHTML =
              '<p class="expired">Code expired</p><p class="instruction" style="margin-top:16px">Open FocusGuard on Mac to generate a new one</p>';
          } else {
            document.getElementById('timer').textContent = 'Disappears in ' + s + ' seconds';
          }
        }, 1000);
      </script>
    ` : `
      <p class="expired">Code expired or already used</p>
      <p class="instruction" style="margin-top:16px">Each code can only be viewed once. Open FocusGuard on Mac to generate a new one.</p>
    `}
  </div>
</body>
</html>`;

  return new Response(html, {
    headers: { "content-type": "text/html;charset=utf-8", "cache-control": "no-store" },
  });
}

/** Generate and serve .mobileconfig profile */
async function handleProfile(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const workerUrl = `${url.protocol}//${url.host}`;

  // Generate unique UUIDs (simple random hex)
  const uuid1 = crypto.randomUUID().toUpperCase();
  const uuid2 = crypto.randomUUID().toUpperCase();

  const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.dnsSettings.managed</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadIdentifier</key>
      <string>com.focusguard.dns.${uuid2}</string>
      <key>PayloadUUID</key>
      <string>${uuid2}</string>
      <key>PayloadDisplayName</key>
      <string>FocusGuard DNS</string>
      <key>PayloadDescription</key>
      <string>Routes DNS through FocusGuard to block distracting websites. Synced with your Mac.</string>
      <key>DNSSettings</key>
      <dict>
        <key>DNSProtocol</key>
        <string>HTTPS</string>
        <key>ServerURL</key>
        <string>${workerUrl}/dns-query</string>
      </dict>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>FocusGuard</string>
  <key>PayloadDescription</key>
  <string>FocusGuard DNS blocker. Synced with your Mac. Blocks distracting websites across all apps.</string>
  <key>PayloadIdentifier</key>
  <string>com.focusguard.profile.${uuid1}</string>
  <key>PayloadOrganization</key>
  <string>FocusGuard</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>${uuid1}</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>`;

  return new Response(plist, {
    headers: {
      "content-type": "application/x-apple-aspen-config",
      "content-disposition": "attachment; filename=FocusGuard.mobileconfig",
    },
  });
}

/** Verify API key for protected endpoints */
function verifyAuth(request: Request, env: Env): boolean {
  const auth = request.headers.get("authorization") || "";
  const token = auth.replace("Bearer ", "");
  return token === env.API_KEY;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // CORS for API endpoints
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "access-control-allow-origin": "*",
          "access-control-allow-methods": "GET, POST, OPTIONS",
          "access-control-allow-headers": "authorization, content-type",
        },
      });
    }

    // DNS-over-HTTPS endpoint (no auth -- standard DoH protocol)
    if (url.pathname === "/dns-query") {
      return handleDnsQuery(request, env);
    }

    // API endpoints (require auth)
    if (url.pathname.startsWith("/api/")) {
      if (!verifyAuth(request, env)) {
        return Response.json({ error: "Unauthorized" }, { status: 401 });
      }

      if (url.pathname === "/api/sync" && request.method === "POST") {
        return handleSync(request, env);
      }

      if (url.pathname === "/api/status" && request.method === "GET") {
        return handleStatus(env);
      }

      if (url.pathname === "/api/setup-code" && request.method === "POST") {
        return handleStoreCode(request, env);
      }

      return Response.json({ error: "Not found" }, { status: 404 });
    }

    // Self-destructing setup page (no auth -- accessed via QR scan)
    if (url.pathname === "/setup") {
      return handleSetupPage(request, env);
    }

    // Serve .mobileconfig profile (scan QR → install → done)
    if (url.pathname === "/profile") {
      return handleProfile(request, env);
    }

    // Health check
    if (url.pathname === "/") {
      return new Response("FocusGuard DNS Proxy");
    }

    return new Response("Not found", { status: 404 });
  },
} satisfies ExportedHandler<Env>;
