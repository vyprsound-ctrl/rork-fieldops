/// Apple App Store — signed data verification for Harbour South's OWN
/// subscription (Apple auto-renewable subscriptions).
///
/// Every piece of subscription data that reaches the database arrives as an
/// Apple JWS (JSON Web Signature): the transaction the app hands over after a
/// StoreKit 2 purchase, its renewal info, and every App Store Server
/// Notification V2. Nothing is trusted until:
///
///   1. the header algorithm is ES256,
///   2. the x5c chain is leaf -> Apple intermediate -> Apple Root CA - G3, with
///      the root byte-identical to the one pinned below,
///   3. each certificate is issued and signed by the next, and was valid at the
///      time Apple signed the data,
///   4. the leaf and intermediate carry Apple's App Store receipt-signing OIDs,
///   5. the ES256 signature over `header.payload` verifies with the leaf key.
///
/// "Issued by" (step 3) means all of: the child's issuer name is byte-identical
/// to the parent's subject name, the parent is a CA (basicConstraints cA=TRUE)
/// whose keyUsage, when present, allows keyCertSign, the child's authority key
/// id matches the parent's subject key id when both are present, and the
/// child's signature verifies with the parent's public key.
///
/// Certificates are parsed and their signatures checked with @peculiar/x509
/// (pure JavaScript ASN.1 + WebCrypto). `node:crypto`'s X509Certificate is NOT
/// used: on the Supabase Edge runtime (Deno 2.1.4) its `checkIssued()` and
/// `verify()` throw "Not implemented". The version is pinned exactly; 2.x needs
/// a reflect-metadata polyfill that Deno 2.1.4 does not load.
///
/// This module has no database or network access, so it can be tested in
/// isolation (`backend/tests/apple-jws.test.ts`).

import * as x509 from "npm:@peculiar/x509@1.14.3";

// Always use the runtime's WebCrypto, never a provider guessed from globals.
x509.cryptoProvider.set(crypto);

/// Apple Root CA - G3, DER, base64.
/// SHA-256 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
/// Source: https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
export const APPLE_ROOT_CA_G3_BASE64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

export const APP_BUNDLE_ID = "com.harboursouth.fieldservice";

/// 1.2.840.113635.100.6.11.1 — Mac App Store receipt signing (leaf).
const LEAF_OID_DER = new Uint8Array([0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x0b, 0x01]);
/// 1.2.840.113635.100.6.2.1 — Apple Worldwide Developer Relations intermediate.
const INTERMEDIATE_OID_DER = new Uint8Array([0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x02, 0x01]);

export class AppleVerificationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AppleVerificationError";
  }
}

export interface VerifyOptions {
  /// Test seam only. Production always uses the pinned Apple root.
  rootDer?: Uint8Array;
  /// Overrides the clock used when the payload carries no signedDate.
  now?: Date;
}

function base64ToBytes(b64: string) {
  const clean = b64.replace(/-/g, "+").replace(/_/g, "/");
  const padded = clean + "=".repeat((4 - (clean.length % 4)) % 4);
  const binary = atob(padded);
  const out = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function contains(haystack: Uint8Array, needle: Uint8Array): boolean {
  outer: for (let i = 0; i <= haystack.length - needle.length; i++) {
    for (let j = 0; j < needle.length; j++) if (haystack[i + j] !== needle[j]) continue outer;
    return true;
  }
  return false;
}

function validAt(cert: x509.X509Certificate, at: Date): boolean {
  return cert.notBefore.getTime() <= at.getTime() && at.getTime() <= cert.notAfter.getTime();
}

/// True only when `cert` was issued and signed by `issuer` (see header, step 3).
async function isIssuedBy(cert: x509.X509Certificate, issuer: x509.X509Certificate): Promise<boolean> {
  try {
    const issuerName = new Uint8Array(cert.issuerName.toArrayBuffer());
    const issuerSubject = new Uint8Array(issuer.subjectName.toArrayBuffer());
    if (!bytesEqual(issuerName, issuerSubject)) return false;

    const constraints = issuer.getExtension(x509.BasicConstraintsExtension);
    if (!constraints?.ca) return false;
    const usage = issuer.getExtension(x509.KeyUsagesExtension);
    if (usage && (usage.usages & x509.KeyUsageFlags.keyCertSign) === 0) return false;

    const authorityKeyId = cert.getExtension(x509.AuthorityKeyIdentifierExtension)?.keyId;
    const subjectKeyId = issuer.getExtension(x509.SubjectKeyIdentifierExtension)?.keyId;
    if (authorityKeyId && subjectKeyId && authorityKeyId.toLowerCase() !== subjectKeyId.toLowerCase()) return false;

    return await cert.verify({ publicKey: issuer.publicKey, signatureOnly: true });
  } catch {
    return false;
  }
}

/// Verifies an Apple JWS and returns its decoded payload.
export async function verifyAppleJws<T = Record<string, unknown>>(
  jws: string,
  options: VerifyOptions = {},
): Promise<T> {
  if (typeof jws !== "string") throw new AppleVerificationError("Signed data is missing.");
  const parts = jws.split(".");
  if (parts.length !== 3) throw new AppleVerificationError("Signed data is not a JWS.");

  let header: { alg?: string; x5c?: string[] };
  let payload: Record<string, unknown>;
  try {
    header = JSON.parse(new TextDecoder().decode(base64ToBytes(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(base64ToBytes(parts[1])));
  } catch {
    throw new AppleVerificationError("Signed data could not be decoded.");
  }

  if (header.alg !== "ES256") throw new AppleVerificationError("Unexpected signing algorithm.");
  if (!Array.isArray(header.x5c) || header.x5c.length < 3) {
    throw new AppleVerificationError("The certificate chain is incomplete.");
  }

  const [leafDer, intermediateDer, rootDer] = header.x5c.slice(0, 3).map(base64ToBytes);
  const trustedRoot = options.rootDer ?? base64ToBytes(APPLE_ROOT_CA_G3_BASE64);
  if (!bytesEqual(rootDer, trustedRoot)) {
    throw new AppleVerificationError("The chain does not end at Apple Root CA - G3.");
  }

  let leaf: x509.X509Certificate, intermediate: x509.X509Certificate, root: x509.X509Certificate;
  try {
    leaf = new x509.X509Certificate(leafDer);
    intermediate = new x509.X509Certificate(intermediateDer);
    root = new x509.X509Certificate(rootDer);
  } catch {
    throw new AppleVerificationError("A certificate in the chain could not be read.");
  }

  if (!(await isIssuedBy(intermediate, root))) {
    throw new AppleVerificationError("The intermediate certificate was not issued by Apple's root.");
  }
  if (!(await isIssuedBy(leaf, intermediate))) {
    throw new AppleVerificationError("The signing certificate was not issued by Apple's intermediate.");
  }
  if (!contains(leafDer, LEAF_OID_DER)) {
    throw new AppleVerificationError("The signing certificate is not an App Store signing certificate.");
  }
  if (!contains(intermediateDer, INTERMEDIATE_OID_DER)) {
    throw new AppleVerificationError("The intermediate certificate is not Apple's WWDR certificate.");
  }

  const signedMs = Number(payload.signedDate ?? NaN);
  const effective = Number.isFinite(signedMs) ? new Date(signedMs) : (options.now ?? new Date());
  if (!validAt(leaf, effective) || !validAt(intermediate, effective) || !validAt(root, effective)) {
    throw new AppleVerificationError("A certificate in the chain was not valid when the data was signed.");
  }

  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey("spki", leaf.publicKey.rawData, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  } catch {
    throw new AppleVerificationError("The signing certificate does not carry an ES256 key.");
  }
  const signature = base64ToBytes(parts[2]);
  const signingInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, signature, signingInput);
  if (!ok) throw new AppleVerificationError("The signature does not match the data.");

  return payload as T;
}

/// The fields of JWSTransactionDecodedPayload this project uses.
export interface AppleTransaction {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  type?: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  offerType?: number;
  offerIdentifier?: string;
  offerDiscountType?: string;
  environment?: string;
  isUpgraded?: boolean;
  signedDate?: number;
}

/// The fields of JWSRenewalInfoDecodedPayload this project uses.
export interface AppleRenewalInfo {
  originalTransactionId: string;
  autoRenewProductId?: string;
  autoRenewStatus?: number;
  isInBillingRetryPeriod?: boolean;
  gracePeriodExpiresDate?: number;
  expirationIntent?: number;
  signedDate?: number;
}

export function expectedBundleId(): string {
  return Deno.env.get("APPLE_BUNDLE_ID") ?? APP_BUNDLE_ID;
}

/// Verifies a transaction and checks it belongs to this app and is a
/// subscription, not some other kind of purchase.
export async function verifyTransaction(jws: string, options: VerifyOptions = {}): Promise<AppleTransaction> {
  const tx = await verifyAppleJws<AppleTransaction>(jws, options);
  if (tx.bundleId !== expectedBundleId()) throw new AppleVerificationError("This purchase is for a different app.");
  if (tx.type && tx.type !== "Auto-Renewable Subscription") {
    throw new AppleVerificationError("This purchase is not a subscription.");
  }
  if (!tx.transactionId || !tx.originalTransactionId || !tx.productId) {
    throw new AppleVerificationError("The transaction is missing required fields.");
  }
  return tx;
}
