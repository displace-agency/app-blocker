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

      return Response.json({ error: "Not found" }, { status: 404 });
    }

    // Health check
    if (url.pathname === "/") {
      return new Response("FocusGuard DNS Proxy");
    }

    return new Response("Not found", { status: 404 });
  },
} satisfies ExportedHandler<Env>;
