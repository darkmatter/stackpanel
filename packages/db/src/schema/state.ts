import { relations } from "drizzle-orm";
import {
	customType,
	index,
	integer,
	pgTable,
	text,
	timestamp,
	uniqueIndex,
} from "drizzle-orm/pg-core";
import { organization } from "./organization";

/**
 * Drizzle doesn't expose `bytea` directly on node-postgres — declare it.
 * Values travel as Buffer on the wire.
 */
const bytea = customType<{ data: Buffer; notNull: false; default: false }>({
	dataType() {
		return "bytea";
	},
});

/**
 * Per-organization Data Encryption Key, wrapped by the master KMS key.
 *
 * Each organization has exactly one DEK. On write:
 *   KMS.Decrypt(encryptedDek) -> raw DEK -> AES-GCM encrypt blob.
 * On read:
 *   KMS.Decrypt(encryptedDek) -> raw DEK -> AES-GCM decrypt blob.
 *
 * Plaintext DEK is never persisted. The master KMS key never leaves AWS.
 * Rotation: insert new DEK row, re-encrypt all org state in a background
 * job, then retire the old row (out of scope for v1).
 */
export const organizationDek = pgTable("organization_dek", {
	organizationId: text("organization_id")
		.primaryKey()
		.references(() => organization.id, { onDelete: "cascade" }),
	encryptedDek: bytea("encrypted_dek").notNull(),
	kmsKeyAlias: text("kms_key_alias").notNull(),
	createdAt: timestamp("created_at").defaultNow().notNull(),
});

/**
 * Encrypted alchemy state entries, one row per (org, stack, stage, fqn).
 *
 * The unique index is the identity of a state entry — alchemy refers to
 * resources by fqn within a stack+stage. `version` enables optimistic
 * concurrency: clients pass the version they read, we reject on mismatch.
 *
 * `nonce` is the 12-byte AES-GCM IV, stored alongside the ciphertext.
 */
export const organizationState = pgTable(
	"organization_state",
	{
		id: text("id").primaryKey(),
		organizationId: text("organization_id")
			.notNull()
			.references(() => organization.id, { onDelete: "cascade" }),
		stack: text("stack").notNull(),
		stage: text("stage").notNull(),
		fqn: text("fqn").notNull(),
		nonce: bytea("nonce").notNull(),
		encryptedBlob: bytea("encrypted_blob").notNull(),
		version: integer("version").notNull().default(1),
		createdAt: timestamp("created_at").defaultNow().notNull(),
		updatedAt: timestamp("updated_at")
			.defaultNow()
			.$onUpdate(() => /* @__PURE__ */ new Date())
			.notNull(),
	},
	(table) => [
		uniqueIndex("organization_state_unique_idx").on(
			table.organizationId,
			table.stack,
			table.stage,
			table.fqn,
		),
		index("organization_state_stage_idx").on(
			table.organizationId,
			table.stack,
			table.stage,
		),
	],
);

export const organizationDekRelations = relations(organizationDek, ({ one }) => ({
	organization: one(organization, {
		fields: [organizationDek.organizationId],
		references: [organization.id],
	}),
}));

export const organizationStateRelations = relations(organizationState, ({ one }) => ({
	organization: one(organization, {
		fields: [organizationState.organizationId],
		references: [organization.id],
	}),
}));
