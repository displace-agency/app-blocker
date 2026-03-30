// DNS wire format parser/builder (RFC 1035)
// Handles only A (type 1) and AAAA (type 28) queries for domain blocking

const TYPE_A = 1;
const TYPE_AAAA = 28;
const CLASS_IN = 1;

export interface DnsQuery {
  id: number;
  domain: string;
  type: number;
  rawQuery: Uint8Array;
}

/** Parse a DNS query from wire format to extract the queried domain */
export function parseDnsQuery(buf: ArrayBuffer): DnsQuery | null {
  const data = new Uint8Array(buf);
  if (data.length < 12) return null;

  const view = new DataView(buf);
  const id = view.getUint16(0);
  const qdcount = view.getUint16(4);

  if (qdcount < 1) return null;

  // Parse question section (starts at byte 12)
  let offset = 12;
  const labels: string[] = [];

  while (offset < data.length) {
    const len = data[offset];
    if (len === 0) {
      offset++;
      break;
    }
    if (len > 63) return null; // compression pointer not expected in queries
    offset++;
    const label = new TextDecoder().decode(data.slice(offset, offset + len));
    labels.push(label);
    offset += len;
  }

  if (offset + 4 > data.length) return null;

  const qtype = view.getUint16(offset);
  // qclass at offset + 2

  return {
    id,
    domain: labels.join(".").toLowerCase(),
    type: qtype,
    rawQuery: data,
  };
}

/** Build a DNS response that returns 0.0.0.0 (A) or :: (AAAA) for a blocked domain */
export function buildBlockedResponse(query: DnsQuery): Uint8Array {
  const raw = query.rawQuery;
  const view = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);

  // Find the end of the question section
  let offset = 12;
  while (offset < raw.length && raw[offset] !== 0) {
    offset += raw[offset] + 1;
  }
  offset++; // skip the null terminator
  offset += 4; // skip qtype + qclass

  const questionSection = raw.slice(12, offset);

  // Response header
  const isAAAA = query.type === TYPE_AAAA;
  const rdataLen = isAAAA ? 16 : 4;
  const rdata = new Uint8Array(rdataLen); // all zeros = 0.0.0.0 or ::

  // Build response
  // Header (12) + Question + Answer (name pointer 2 + type 2 + class 2 + ttl 4 + rdlength 2 + rdata)
  const answerLen = 2 + 2 + 2 + 4 + 2 + rdataLen;
  const response = new Uint8Array(12 + questionSection.length + answerLen);
  const respView = new DataView(response.buffer);

  // Header
  respView.setUint16(0, query.id); // ID
  respView.setUint16(2, 0x8180); // Flags: QR=1, RD=1, RA=1
  respView.setUint16(4, 1); // QDCOUNT
  respView.setUint16(6, 1); // ANCOUNT
  respView.setUint16(8, 0); // NSCOUNT
  respView.setUint16(10, 0); // ARCOUNT

  // Question section (copy from query)
  response.set(questionSection, 12);

  // Answer section
  let ansOffset = 12 + questionSection.length;
  respView.setUint16(ansOffset, 0xc00c); // Name pointer to offset 12 (question domain)
  ansOffset += 2;
  respView.setUint16(ansOffset, query.type); // Type (A or AAAA)
  ansOffset += 2;
  respView.setUint16(ansOffset, CLASS_IN); // Class IN
  ansOffset += 2;
  respView.setUint32(ansOffset, 60); // TTL: 60 seconds
  ansOffset += 4;
  respView.setUint16(ansOffset, rdataLen); // RDLENGTH
  ansOffset += 2;
  response.set(rdata, ansOffset); // RDATA (0.0.0.0 or ::)

  return response;
}

/** Check if a domain or any of its parent domains is in the blocklist */
export function isDomainBlocked(domain: string, blocklist: Set<string>): boolean {
  // Check exact match
  if (blocklist.has(domain)) return true;

  // Check parent domains (e.g. "sub.x.com" blocked by "x.com")
  const parts = domain.split(".");
  for (let i = 1; i < parts.length - 1; i++) {
    const parent = parts.slice(i).join(".");
    if (blocklist.has(parent)) return true;
  }

  return false;
}
