import { getDb, state as stateSchema } from "@stackpanel/db";
import { AwsClient } from "aws4fetch";
import { eq } from "drizzle-orm";

/**
 * Envelope encryption for organization state.
 *
 * Data flow:
 *   master KMS key  ─encrypts─▶  per-org DEK (32 random bytes)
 *                                       │ (stored as ciphertext in `organization_dek`)
 *                                       ▼
 *                               AES-256-GCM encrypts state blob
 *                                       │ (stored in `organization_state`)
 *                                       ▼
 *                               ciphertext + nonce + auth tag
 *
 * Plaintext DEK never touches disk. Master key never leaves AWS KMS.
 * Runs on both Node and Cloudflare Workers: Web Crypto API for AES-GCM,
 * aws4fetch for KMS calls (no Node-only AWS SDK handler).
 *
 * One KMS call per read/write per org — cheap enough without a cache for v1.
 * Add a TTL cache for the decrypted DEK if KMS call volume becomes a concern.
 */

const DEFAULT_KMS_ALIAS = "alias/stackpanel-secrets";
const DEK_BYTES = 32;
const NONCE_BYTES = 12;
const GCM_TAG_BYTES = 16;

function kmsAlias(): string {
	return getEnv("STACKPANEL_KMS_ALIAS") ?? DEFAULT_KMS_ALIAS;
}

function awsRegion(): string {
	return getEnv("AWS_REGION") ?? "us-east-1";
}

/**
 * Env lookup that works on both runtimes:
 *  - Node / Bun: `process.env`
 *  - CF Workers: bindings injected on the request context via a globalThis shim
 *
 * apps/api wires the Worker's `env` into `globalThis.__env` at request entry so
 * library code can read secrets without threading env through every call site.
 */
function getEnv(name: string): string | undefined {
	const globalEnv = (globalThis as { __env?: Record<string, string> }).__env;
	if (globalEnv && name in globalEnv) return globalEnv[name];
	if (typeof process !== "undefined" && process.env) return process.env[name];
	return undefined;
}

let _kms: AwsClient | undefined;
function kms(): AwsClient {
	if (_kms) return _kms;
	const accessKeyId = getEnv("AWS_ACCESS_KEY_ID");
	const secretAccessKey = getEnv("AWS_SECRET_ACCESS_KEY");
	if (!accessKeyId || !secretAccessKey) {
		throw new Error(
			"AWS credentials missing — set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY",
		);
	}
	_kms = new AwsClient({
		accessKeyId,
		secretAccessKey,
		service: "kms",
		region: awsRegion(),
	});
	return _kms;
}

/**
 * KMS Encrypt via the JSON POST API (no SDK). Returns the wrapped DEK.
 */
async function kmsEncrypt(plaintext: Uint8Array, keyId: string): Promise<Uint8Array> {
	const url = `https://kms.${awsRegion()}.amazonaws.com/`;
	const body = JSON.stringify({
		KeyId: keyId,
		Plaintext: toBase64(plaintext),
	});
	const res = await kms().fetch(url, {
		method: "POST",
		headers: {
			"Content-Type": "application/x-amz-json-1.1",
			"X-Amz-Target": "TrentService.Encrypt",
		},
		body,
	});
	if (!res.ok) {
		throw new Error(`KMS Encrypt failed: ${res.status} ${await res.text()}`);
	}
	const payload = (await res.json()) as { CiphertextBlob: string };
	return fromBase64(payload.CiphertextBlob);
}

async function kmsDecrypt(
	ciphertext: Uint8Array,
	keyId: string,
): Promise<Uint8Array> {
	const url = `https://kms.${awsRegion()}.amazonaws.com/`;
	const body = JSON.stringify({
		KeyId: keyId,
		CiphertextBlob: toBase64(ciphertext),
	});
	const res = await kms().fetch(url, {
		method: "POST",
		headers: {
			"Content-Type": "application/x-amz-json-1.1",
			"X-Amz-Target": "TrentService.Decrypt",
		},
		body,
	});
	if (!res.ok) {
		throw new Error(`KMS Decrypt failed: ${res.status} ${await res.text()}`);
	}
	const payload = (await res.json()) as { Plaintext: string };
	return fromBase64(payload.Plaintext);
}

/**
 * Resolve the organization's raw DEK, creating a new wrapped DEK via KMS
 * on first access. Caller receives 32 plaintext bytes — MUST NOT persist.
 */
async function resolveDek(organizationId: string): Promise<Uint8Array> {
	const db = getDb();
	const existing = await db
		.select()
		.from(stateSchema.organizationDek)
		.where(eq(stateSchema.organizationDek.organizationId, organizationId))
		.limit(1);

	if (existing[0]) {
		return kmsDecrypt(
			new Uint8Array(existing[0].encryptedDek),
			existing[0].kmsKeyAlias,
		);
	}

	const alias = kmsAlias();
	const dek = new Uint8Array(DEK_BYTES);
	crypto.getRandomValues(dek);
	const encryptedDek = await kmsEncrypt(dek, alias);

	await db
		.insert(stateSchema.organizationDek)
		.values({
			organizationId,
			encryptedDek: Buffer.from(encryptedDek),
			kmsKeyAlias: alias,
		})
		.onConflictDoNothing();

	return dek;
}

export type EncryptedPayload = {
	nonce: Buffer;
	ciphertext: Buffer;
};

/**
 * Encrypt an arbitrary UTF-8 string (typically JSON) with the organization's
 * DEK. The Web Crypto AES-GCM implementation already appends the 16-byte auth
 * tag to the ciphertext — no separate column needed.
 */
export async function encryptForOrganization(
	organizationId: string,
	plaintext: string,
): Promise<EncryptedPayload> {
	const dek = await resolveDek(organizationId);
	const nonce = new Uint8Array(NONCE_BYTES);
	crypto.getRandomValues(nonce);
	const key = await crypto.subtle.importKey(
		"raw",
		toBufferSource(dek),
		{ name: "AES-GCM" },
		false,
		["encrypt"],
	);
	const encoded = new TextEncoder().encode(plaintext);
	const encrypted = await crypto.subtle.encrypt(
		{ name: "AES-GCM", iv: toBufferSource(nonce), tagLength: GCM_TAG_BYTES * 8 },
		key,
		toBufferSource(encoded),
	);
	return {
		nonce: Buffer.from(nonce),
		ciphertext: Buffer.from(new Uint8Array(encrypted)),
	};
}

/**
 * Decrypt a payload previously produced by `encryptForOrganization`.
 * Throws if the auth tag doesn't verify (integrity failure) or the DEK
 * can't be unwrapped.
 */
export async function decryptForOrganization(
	organizationId: string,
	payload: EncryptedPayload,
): Promise<string> {
	const dek = await resolveDek(organizationId);
	const key = await crypto.subtle.importKey(
		"raw",
		toBufferSource(dek),
		{ name: "AES-GCM" },
		false,
		["decrypt"],
	);
	const plaintext = await crypto.subtle.decrypt(
		{
			name: "AES-GCM",
			iv: toBufferSource(payload.nonce),
			tagLength: GCM_TAG_BYTES * 8,
		},
		key,
		toBufferSource(payload.ciphertext),
	);
	return new TextDecoder().decode(plaintext);
}

/**
 * Web Crypto's `BufferSource` narrowed past TS 5.7 rejects
 * `Uint8Array<ArrayBufferLike>` (which may alias SharedArrayBuffer). Copy
 * into a fresh ArrayBuffer-backed view before handing to subtle.
 */
function toBufferSource(input: Uint8Array | Buffer): ArrayBuffer {
	const view = input instanceof Buffer ? new Uint8Array(input) : input;
	const copy = new ArrayBuffer(view.byteLength);
	new Uint8Array(copy).set(view);
	return copy;
}

function toBase64(bytes: Uint8Array): string {
	let binary = "";
	for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]!);
	return btoa(binary);
}

function fromBase64(b64: string): Uint8Array {
	const binary = atob(b64);
	const bytes = new Uint8Array(binary.length);
	for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
	return bytes;
}
