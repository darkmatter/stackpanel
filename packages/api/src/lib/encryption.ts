import { DecryptCommand, EncryptCommand, KMSClient } from "@aws-sdk/client-kms";
import { getDb, state as stateSchema } from "@stackpanel/db";
import { randomBytes, createCipheriv, createDecipheriv } from "node:crypto";
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
 * One KMS call per read/write per org — cheap enough without a cache for v1.
 * Add a TTL cache for the decrypted DEK if KMS call volume becomes a concern.
 */

const DEFAULT_KMS_ALIAS = "alias/stackpanel-secrets";
const AES_ALGO = "aes-256-gcm";
const DEK_BYTES = 32;
const NONCE_BYTES = 12;

let _kms: KMSClient | undefined;
function kms(): KMSClient {
	if (!_kms) _kms = new KMSClient({});
	return _kms;
}

function kmsAlias(): string {
	return process.env.STACKPANEL_KMS_ALIAS ?? DEFAULT_KMS_ALIAS;
}

/**
 * Resolve the organization's raw DEK, creating a new wrapped DEK via KMS
 * on first access. Caller receives 32 plaintext bytes — MUST NOT persist.
 */
async function resolveDek(organizationId: string): Promise<Buffer> {
	const db = getDb();
	const existing = await db
		.select()
		.from(stateSchema.organizationDek)
		.where(eq(stateSchema.organizationDek.organizationId, organizationId))
		.limit(1);

	if (existing[0]) {
		const { Plaintext } = await kms().send(
			new DecryptCommand({
				CiphertextBlob: existing[0].encryptedDek,
				KeyId: existing[0].kmsKeyAlias,
			}),
		);
		if (!Plaintext) throw new Error("KMS Decrypt returned empty Plaintext");
		return Buffer.from(Plaintext);
	}

	const alias = kmsAlias();
	const dek = randomBytes(DEK_BYTES);
	const { CiphertextBlob } = await kms().send(
		new EncryptCommand({ KeyId: alias, Plaintext: dek }),
	);
	if (!CiphertextBlob) throw new Error("KMS Encrypt returned empty CiphertextBlob");

	await db
		.insert(stateSchema.organizationDek)
		.values({
			organizationId,
			encryptedDek: Buffer.from(CiphertextBlob),
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
 * DEK. The auth tag is appended to the ciphertext so decryption can verify
 * integrity without a separate column.
 */
export async function encryptForOrganization(
	organizationId: string,
	plaintext: string,
): Promise<EncryptedPayload> {
	const dek = await resolveDek(organizationId);
	const nonce = randomBytes(NONCE_BYTES);
	const cipher = createCipheriv(AES_ALGO, dek, nonce);
	const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
	const authTag = cipher.getAuthTag();
	return {
		nonce,
		ciphertext: Buffer.concat([encrypted, authTag]),
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
	// GCM auth tag is the last 16 bytes of the stored ciphertext.
	const authTag = payload.ciphertext.subarray(payload.ciphertext.length - 16);
	const encrypted = payload.ciphertext.subarray(0, payload.ciphertext.length - 16);
	const decipher = createDecipheriv(AES_ALGO, dek, payload.nonce);
	decipher.setAuthTag(authTag);
	const plaintext = Buffer.concat([decipher.update(encrypted), decipher.final()]);
	return plaintext.toString("utf8");
}
