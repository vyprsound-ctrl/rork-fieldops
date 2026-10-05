// Harbour South FieldOps — Apple JWS verification tests (DEVELOPMENT TOOLING)
//
// Run:  deno test -A backend/tests/apple-jws.test.ts
//
// Builds a throwaway three-level certificate chain with openssl at test time
// (root -> intermediate -> leaf, carrying Apple's App Store OIDs), signs JWS
// payloads with the leaf key, and proves `verifyAppleJws` accepts exactly the
// genuine ones. The real pinned Apple root is tested too: a chain signed by
// anything else must be refused. No private key is stored in the repository.

import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { X509Certificate as NodeX509Certificate } from "node:crypto";
import {
  APPLE_ROOT_CA_G3_BASE64,
  AppleVerificationError,
  verifyAppleJws,
  verifyTransaction,
} from "../functions/_shared/apple.ts";

const dir = await Deno.makeTempDir();

async function sh(args: string[]) {
  const out = await new Deno.Command("openssl", { args, cwd: dir, stderr: "piped", stdout: "piped" }).output();
  if (!out.success) throw new Error(new TextDecoder().decode(out.stderr));
}

await Deno.writeTextFile(`${dir}/ext.cnf`, `
[root]
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
[inter]
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
1.2.840.113635.100.6.2.1=ASN1:NULL
[leaf]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
1.2.840.113635.100.6.11.1=ASN1:NULL
[plainleaf]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
[intercannotsign]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
1.2.840.113635.100.6.2.1=ASN1:NULL
`);

async function makeChain(prefix: string, leafExt = "leaf", interExt = "inter") {
  await sh(["ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", `${prefix}root.key`]);
  await sh(["req", "-new", "-x509", "-key", `${prefix}root.key`, "-subj", `/CN=${prefix} Root`, "-days", "3650",
    "-sha384", "-extensions", "root", "-config", "ext.cnf", "-out", `${prefix}root.pem`]);
  await sh(["ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", `${prefix}inter.key`]);
  await sh(["req", "-new", "-key", `${prefix}inter.key`, "-subj", `/CN=${prefix} Inter`, "-out", `${prefix}inter.csr`]);
  await sh(["x509", "-req", "-in", `${prefix}inter.csr`, "-CA", `${prefix}root.pem`, "-CAkey", `${prefix}root.key`,
    "-CAcreateserial", "-days", "3650", "-sha384", "-extfile", "ext.cnf", "-extensions", interExt, "-out", `${prefix}inter.pem`]);
  await sh(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", `${prefix}leaf.key`]);
  await sh(["pkcs8", "-topk8", "-nocrypt", "-in", `${prefix}leaf.key`, "-outform", "DER", "-out", `${prefix}leaf.p8`]);
  await sh(["req", "-new", "-key", `${prefix}leaf.key`, "-subj", `/CN=${prefix} Leaf`, "-out", `${prefix}leaf.csr`]);
  await sh(["x509", "-req", "-in", `${prefix}leaf.csr`, "-CA", `${prefix}inter.pem`, "-CAkey", `${prefix}inter.key`,
    "-CAcreateserial", "-days", "3650", "-sha384", "-extfile", "ext.cnf", "-extensions", leafExt, "-out", `${prefix}leaf.pem`]);
  for (const n of ["root", "inter", "leaf"]) {
    await sh(["x509", "-in", `${prefix}${n}.pem`, "-outform", "DER", "-out", `${prefix}${n}.der`]);
  }
  const der = async (n: string) => await Deno.readFile(`${dir}/${prefix}${n}.der`);
  const key = await crypto.subtle.importKey("pkcs8", await Deno.readFile(`${dir}/${prefix}leaf.p8`),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  return { root: await der("root"), inter: await der("inter"), leaf: await der("leaf"), key };
}

const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
const b64url = (b: Uint8Array) => b64(b).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

async function sign(chain: Awaited<ReturnType<typeof makeChain>>, payload: unknown, x5c?: string[], alg = "ES256") {
  const header = { alg, x5c: x5c ?? [b64(chain.leaf), b64(chain.inter), b64(chain.root)] };
  const h = b64url(new TextEncoder().encode(JSON.stringify(header)));
  const p = b64url(new TextEncoder().encode(JSON.stringify(payload)));
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, chain.key, new TextEncoder().encode(`${h}.${p}`)));
  return `${h}.${p}.${b64url(sig)}`;
}

const good = await makeChain("a");
const other = await makeChain("b");
const noOid = await makeChain("c", "plainleaf");
const nonCaInter = await makeChain("d", "leaf", "intercannotsign");

const tx = {
  transactionId: "2000000000000001",
  originalTransactionId: "2000000000000001",
  bundleId: "com.harboursouth.fieldservice",
  productId: "com.harboursouth.fieldservice.team.monthly",
  type: "Auto-Renewable Subscription",
  offerType: 1,
  offerDiscountType: "FREE_TRIAL",
  signedDate: Date.now(),
};

Deno.test("A genuine chain and signature verify and return the payload", async () => {
  const jws = await sign(good, tx);
  const out = await verifyTransaction(jws, { rootDer: good.root });
  assertEquals(out.productId, tx.productId);
  assertEquals(out.offerType, 1);
});

Deno.test("A payload altered after signing is refused", async () => {
  const jws = await sign(good, tx);
  const [h, , s] = jws.split(".");
  const forged = b64url(new TextEncoder().encode(JSON.stringify({ ...tx, productId: "com.harboursouth.fieldservice.business.annual" })));
  await assertRejects(() => verifyAppleJws(`${h}.${forged}.${s}`, { rootDer: good.root }), AppleVerificationError, "signature");
});

Deno.test("A chain from a different root is refused", async () => {
  const jws = await sign(other, tx);
  await assertRejects(() => verifyAppleJws(jws, { rootDer: good.root }), AppleVerificationError, "Apple Root");
});

Deno.test("In production only Apple Root CA - G3 is trusted", async () => {
  const jws = await sign(good, tx);
  await assertRejects(() => verifyAppleJws(jws), AppleVerificationError, "Apple Root CA - G3");
  assert(APPLE_ROOT_CA_G3_BASE64.length > 500);
});

Deno.test("A leaf swapped in from another chain is refused", async () => {
  const jws = await sign(other, tx, [b64(other.leaf), b64(good.inter), b64(good.root)]);
  await assertRejects(() => verifyAppleJws(jws, { rootDer: good.root }), AppleVerificationError, "issued");
});

Deno.test("A leaf without the App Store signing OID is refused", async () => {
  const jws = await sign(noOid, tx);
  await assertRejects(() => verifyAppleJws(jws, { rootDer: noOid.root }), AppleVerificationError, "App Store signing");
});

Deno.test("A non-ES256 header is refused", async () => {
  const jws = await sign(good, tx, undefined, "HS256");
  await assertRejects(() => verifyAppleJws(jws, { rootDer: good.root }), AppleVerificationError, "algorithm");
});

Deno.test("A short chain is refused", async () => {
  const jws = await sign(good, tx, [b64(good.leaf)]);
  await assertRejects(() => verifyAppleJws(jws, { rootDer: good.root }), AppleVerificationError, "incomplete");
});

Deno.test("A purchase for another app is refused", async () => {
  const jws = await sign(good, { ...tx, bundleId: "com.example.other" });
  await assertRejects(() => verifyTransaction(jws, { rootDer: good.root }), AppleVerificationError, "different app");
});

Deno.test("A non-subscription purchase is refused", async () => {
  const jws = await sign(good, { ...tx, type: "Consumable" });
  await assertRejects(() => verifyTransaction(jws, { rootDer: good.root }), AppleVerificationError, "not a subscription");
});

Deno.test("Data signed outside the certificates' validity is refused", async () => {
  const jws = await sign(good, { ...tx, signedDate: Date.parse("2001-01-01T00:00:00Z") });
  await assertRejects(() => verifyAppleJws(jws, { rootDer: good.root }), AppleVerificationError, "not valid");
});

Deno.test("Garbage is refused, never thrown as an unexpected error", async () => {
  await assertRejects(() => verifyAppleJws("not-a-jws", { rootDer: good.root }), AppleVerificationError);
  await assertRejects(() => verifyAppleJws("a.b.c", { rootDer: good.root }), AppleVerificationError);
});

// ── Supabase Edge runtime compatibility (Deno 2.1.4) ─────────────────────────
// On the live runtime node:crypto's X509Certificate.checkIssued() and .verify()
// throw "Not implemented". These tests make them throw here too, on any Deno,
// so a regression back to them fails locally instead of in production.

async function withNodeX509Disabled(fn: () => Promise<void>) {
  const proto = NodeX509Certificate.prototype as unknown as Record<string, unknown>;
  const saved = { checkIssued: proto.checkIssued, verify: proto.verify };
  const notImplemented = (name: string) => () => {
    throw new Error(`Not implemented: crypto.X509Certificate.prototype.${name}`);
  };
  proto.checkIssued = notImplemented("checkIssued");
  proto.verify = notImplemented("verify");
  try {
    await fn();
  } finally {
    proto.checkIssued = saved.checkIssued;
    proto.verify = saved.verify;
  }
}

Deno.test("The verifier does not depend on node:crypto X509Certificate", async () => {
  const source = await Deno.readTextFile(new URL("../functions/_shared/apple.ts", import.meta.url));
  assert(!/from\s+"node:crypto"/.test(source), "apple.ts must not import node:crypto");
  assert(!/\.checkIssued\(/.test(source), "apple.ts must not call checkIssued()");
});

Deno.test("A genuine chain verifies with checkIssued()/verify() unavailable", async () => {
  await withNodeX509Disabled(async () => {
    const out = await verifyTransaction(await sign(good, tx), { rootDer: good.root });
    assertEquals(out.transactionId, tx.transactionId);
  });
});

Deno.test("A leaf swapped in from another chain is refused with checkIssued()/verify() unavailable", async () => {
  await withNodeX509Disabled(async () => {
    const jws = await sign(other, tx, [b64(other.leaf), b64(good.inter), b64(good.root)]);
    await assertRejects(() => verifyAppleJws(jws, { rootDer: good.root }), AppleVerificationError, "issued");
  });
});

Deno.test("An intermediate swapped in from another chain is refused", async () => {
  const jws = await sign(good, tx, [b64(good.leaf), b64(other.inter), b64(good.root)]);
  await assertRejects(() => verifyAppleJws(jws, { rootDer: good.root }), AppleVerificationError, "issued by Apple's root");
});

Deno.test("A certificate whose signature was tampered with is refused", async () => {
  const tampered = good.leaf.slice();
  tampered[tampered.length - 1] ^= 0x01;
  const jws = await sign(good, tx, [b64(tampered), b64(good.inter), b64(good.root)]);
  await assertRejects(() => verifyAppleJws(jws, { rootDer: good.root }), AppleVerificationError, "issued");
});

Deno.test("A leaf issued by a non-CA intermediate is refused", async () => {
  const jws = await sign(nonCaInter, tx);
  await assertRejects(() => verifyAppleJws(jws, { rootDer: nonCaInter.root }), AppleVerificationError, "issued");
});

// Apple's real production chain, as published in Apple's own
// app-store-server-library test suite (public certificates only; the
// intermediate is byte-identical to apple.com AppleWWDRCAG6.cer). The JWS
// signature is not Apple's, so verification must get through every chain check
// and stop exactly at the signature: that proves the pinned production root,
// issuance, certificate signatures, OIDs and validity window all pass.
const REAL_APPLE_INTERMEDIATE =
  "MIIDFjCCApygAwIBAgIUIsGhRwp0c2nvU4YSycafPTjzbNcwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMjEwMzE3MjAzNzEwWhcNMzYwMzE5MDAwMDAwWjB1MUQwQgYDVQQDDDtBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9ucyBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTELMAkGA1UECwwCRzYxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEbsQKC94PrlWmZXnXgtxzdVJL8T0SGYngDRGpngn3N6PT8JMEb7FDi4bBmPhCnZ3/sq6PF/cGcKXWsL5vOteRhyJ45x3ASP7cOB+aao90fcpxSv/EZFbniAbNgZGhIhpIo4H6MIH3MBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUu7DeoVgziJqkipnevr3rr9rLJKswRgYIKwYBBQUHAQEEOjA4MDYGCCsGAQUFBzABhipodHRwOi8vb2NzcC5hcHBsZS5jb20vb2NzcDAzLWFwcGxlcm9vdGNhZzMwNwYDVR0fBDAwLjAsoCqgKIYmaHR0cDovL2NybC5hcHBsZS5jb20vYXBwbGVyb290Y2FnMy5jcmwwHQYDVR0OBBYEFD8vlCNR01DJmig97bB85c+lkGKZMA4GA1UdDwEB/wQEAwIBBjAQBgoqhkiG92NkBgIBBAIFADAKBggqhkjOPQQDAwNoADBlAjBAXhSq5IyKogMCPtw490BaB677CaEGJXufQB/EqZGd6CSjiCtOnuMTbXVXmxxcxfkCMQDTSPxarZXvNrkxU3TkUMI33yzvFVVRT4wxWJC994OsdcZ4+RGNsYDyR5gmdr0nDGg=";
const REAL_APPLE_SIGNING_CERTIFICATE =
  "MIIEMTCCA7agAwIBAgIQR8KHzdn554Z/UoradNx9tzAKBggqhkjOPQQDAzB1MUQwQgYDVQQDDDtBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9ucyBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTELMAkGA1UECwwCRzYxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMB4XDTI1MDkxOTE5NDQ1MVoXDTI3MTAxMzE3NDcyM1owgZIxQDA+BgNVBAMMN1Byb2QgRUNDIE1hYyBBcHAgU3RvcmUgYW5kIGlUdW5lcyBTdG9yZSBSZWNlaXB0IFNpZ25pbmcxLDAqBgNVBAsMI0FwcGxlIFdvcmxkd2lkZSBEZXZlbG9wZXIgUmVsYXRpb25zMRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABNnVvhcv7iT+7Ex5tBMBgrQspHzIsXRi0Yxfek7lv8wEmj/bHiWtNwJqc2BoHzsQiEjP7KFIIKg4Y8y0/nynuAmjggIIMIICBDAMBgNVHRMBAf8EAjAAMB8GA1UdIwQYMBaAFD8vlCNR01DJmig97bB85c+lkGKZMHAGCCsGAQUFBwEBBGQwYjAtBggrBgEFBQcwAoYhaHR0cDovL2NlcnRzLmFwcGxlLmNvbS93d2RyZzYuZGVyMDEGCCsGAQUFBzABhiVodHRwOi8vb2NzcC5hcHBsZS5jb20vb2NzcDAzLXd3ZHJnNjAyMIIBHgYDVR0gBIIBFTCCAREwggENBgoqhkiG92NkBQYBMIH+MIHDBggrBgEFBQcCAjCBtgyBs1JlbGlhbmNlIG9uIHRoaXMgY2VydGlmaWNhdGUgYnkgYW55IHBhcnR5IGFzc3VtZXMgYWNjZXB0YW5jZSBvZiB0aGUgdGhlbiBhcHBsaWNhYmxlIHN0YW5kYXJkIHRlcm1zIGFuZCBjb25kaXRpb25zIG9mIHVzZSwgY2VydGlmaWNhdGUgcG9saWN5IGFuZCBjZXJ0aWZpY2F0aW9uIHByYWN0aWNlIHN0YXRlbWVudHMuMDYGCCsGAQUFBwIBFipodHRwOi8vd3d3LmFwcGxlLmNvbS9jZXJ0aWZpY2F0ZWF1dGhvcml0eS8wHQYDVR0OBBYEFIFioG4wMMVA1ku9zJmGNPAVn3eqMA4GA1UdDwEB/wQEAwIHgDAQBgoqhkiG92NkBgsBBAIFADAKBggqhkjOPQQDAwNpADBmAjEA+qXnREC7hXIWVLsLxznjRpIzPf7VHz9V/CTm8+LJlrQepnmcPvGLNcX6XPnlcgLAAjEA5IjNZKgg5pQ79knF4IbTXdKv8vutIDMXDmjPVT3dGvFtsGRwXOywR2kZCdSrfeot";
const REAL_SIGNED_DATE = Date.parse("2026-10-05T04:08:00Z");

function realChainJws(x5c: string[], payload: unknown = { ...tx, signedDate: REAL_SIGNED_DATE }) {
  const h = b64url(new TextEncoder().encode(JSON.stringify({ alg: "ES256", x5c })));
  const p = b64url(new TextEncoder().encode(JSON.stringify(payload)));
  return `${h}.${p}.${b64url(new Uint8Array(64))}`;
}

Deno.test("Apple's real production chain passes every certificate check to the pinned root", async () => {
  await withNodeX509Disabled(async () => {
    const jws = realChainJws([REAL_APPLE_SIGNING_CERTIFICATE, REAL_APPLE_INTERMEDIATE, APPLE_ROOT_CA_G3_BASE64]);
    await assertRejects(() => verifyAppleJws(jws), AppleVerificationError, "signature does not match");
  });
});

Deno.test("Apple's real leaf is refused under a non-Apple intermediate", async () => {
  const jws = realChainJws([REAL_APPLE_SIGNING_CERTIFICATE, b64(good.inter), APPLE_ROOT_CA_G3_BASE64]);
  await assertRejects(() => verifyAppleJws(jws), AppleVerificationError, "issued by Apple's root");
});

Deno.test("A self-made leaf is refused under Apple's real intermediate and root", async () => {
  const jws = realChainJws([b64(good.leaf), REAL_APPLE_INTERMEDIATE, APPLE_ROOT_CA_G3_BASE64]);
  await assertRejects(() => verifyAppleJws(jws), AppleVerificationError, "issued by Apple's intermediate");
});

Deno.test("Apple's real chain is refused for data signed after the leaf expired", async () => {
  const jws = realChainJws(
    [REAL_APPLE_SIGNING_CERTIFICATE, REAL_APPLE_INTERMEDIATE, APPLE_ROOT_CA_G3_BASE64],
    { ...tx, signedDate: Date.parse("2028-01-01T00:00:00Z") },
  );
  await assertRejects(() => verifyAppleJws(jws), AppleVerificationError, "not valid");
});
