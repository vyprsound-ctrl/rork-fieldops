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
`);

async function makeChain(prefix: string, leafExt = "leaf") {
  await sh(["ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", `${prefix}root.key`]);
  await sh(["req", "-new", "-x509", "-key", `${prefix}root.key`, "-subj", `/CN=${prefix} Root`, "-days", "3650",
    "-sha384", "-extensions", "root", "-config", "ext.cnf", "-out", `${prefix}root.pem`]);
  await sh(["ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", `${prefix}inter.key`]);
  await sh(["req", "-new", "-key", `${prefix}inter.key`, "-subj", `/CN=${prefix} Inter`, "-out", `${prefix}inter.csr`]);
  await sh(["x509", "-req", "-in", `${prefix}inter.csr`, "-CA", `${prefix}root.pem`, "-CAkey", `${prefix}root.key`,
    "-CAcreateserial", "-days", "3650", "-sha384", "-extfile", "ext.cnf", "-extensions", "inter", "-out", `${prefix}inter.pem`]);
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
