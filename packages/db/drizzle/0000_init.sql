CREATE TABLE "account" (
	"id" text PRIMARY KEY NOT NULL,
	"account_id" text NOT NULL,
	"provider_id" text NOT NULL,
	"user_id" text NOT NULL,
	"access_token" text,
	"refresh_token" text,
	"id_token" text,
	"access_token_expires_at" timestamp,
	"refresh_token_expires_at" timestamp,
	"scope" text,
	"password" text,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp NOT NULL
);
--> statement-breakpoint
CREATE TABLE "session" (
	"id" text PRIMARY KEY NOT NULL,
	"expires_at" timestamp NOT NULL,
	"token" text NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp NOT NULL,
	"ip_address" text,
	"user_agent" text,
	"user_id" text NOT NULL,
	"active_organization_id" text,
	CONSTRAINT "session_token_unique" UNIQUE("token")
);
--> statement-breakpoint
CREATE TABLE "user" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"email" text NOT NULL,
	"email_verified" boolean DEFAULT false NOT NULL,
	"image" text,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "user_email_unique" UNIQUE("email")
);
--> statement-breakpoint
CREATE TABLE "verification" (
	"id" text PRIMARY KEY NOT NULL,
	"identifier" text NOT NULL,
	"value" text NOT NULL,
	"expires_at" timestamp NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "invitation" (
	"id" text PRIMARY KEY NOT NULL,
	"email" text NOT NULL,
	"inviter_id" text NOT NULL,
	"organization_id" text NOT NULL,
	"role" text,
	"status" text NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"expires_at" timestamp NOT NULL
);
--> statement-breakpoint
CREATE TABLE "member" (
	"id" text PRIMARY KEY NOT NULL,
	"organization_id" text NOT NULL,
	"user_id" text NOT NULL,
	"role" text NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "organization" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"slug" text NOT NULL,
	"logo" text,
	"metadata" text,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "organization_dek" (
	"organization_id" text PRIMARY KEY NOT NULL,
	"encrypted_dek" "bytea" NOT NULL,
	"kms_key_alias" text NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "organization_state" (
	"id" text PRIMARY KEY NOT NULL,
	"organization_id" text NOT NULL,
	"stack" text NOT NULL,
	"stage" text NOT NULL,
	"fqn" text NOT NULL,
	"nonce" "bytea" NOT NULL,
	"encrypted_blob" "bytea" NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "polar_event" (
	"id" text PRIMARY KEY NOT NULL,
	"polar_event_id" text NOT NULL,
	"event_type" text NOT NULL,
	"payload" text NOT NULL,
	"processed_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "user_subscription" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"polar_customer_id" text NOT NULL,
	"polar_subscription_id" text,
	"plan" text DEFAULT 'free' NOT NULL,
	"status" text DEFAULT 'active' NOT NULL,
	"current_period_end" timestamp,
	"cancel_at_period_end" text,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "beta_waitlist" (
	"id" text PRIMARY KEY NOT NULL,
	"email" text NOT NULL,
	"name" text,
	"company" text,
	"role" text,
	"source" text,
	"notes" text,
	"referrer" text,
	"user_agent" text,
	"ip_hash" text,
	"invited_at" timestamp,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "account" ADD CONSTRAINT "account_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "session" ADD CONSTRAINT "session_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "invitation" ADD CONSTRAINT "invitation_inviter_id_user_id_fk" FOREIGN KEY ("inviter_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "invitation" ADD CONSTRAINT "invitation_organization_id_organization_id_fk" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "member" ADD CONSTRAINT "member_organization_id_organization_id_fk" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "member" ADD CONSTRAINT "member_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "organization_dek" ADD CONSTRAINT "organization_dek_organization_id_organization_id_fk" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "organization_state" ADD CONSTRAINT "organization_state_organization_id_organization_id_fk" FOREIGN KEY ("organization_id") REFERENCES "public"."organization"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_subscription" ADD CONSTRAINT "user_subscription_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "account_userId_idx" ON "account" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "session_userId_idx" ON "session" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "verification_identifier_idx" ON "verification" USING btree ("identifier");--> statement-breakpoint
CREATE INDEX "invitation_org_idx" ON "invitation" USING btree ("organization_id");--> statement-breakpoint
CREATE UNIQUE INDEX "member_org_user_idx" ON "member" USING btree ("organization_id","user_id");--> statement-breakpoint
CREATE INDEX "member_user_idx" ON "member" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "organization_slug_idx" ON "organization" USING btree ("slug");--> statement-breakpoint
CREATE UNIQUE INDEX "organization_state_unique_idx" ON "organization_state" USING btree ("organization_id","stack","stage","fqn");--> statement-breakpoint
CREATE INDEX "organization_state_stage_idx" ON "organization_state" USING btree ("organization_id","stack","stage");--> statement-breakpoint
CREATE UNIQUE INDEX "polar_event_polar_id_idx" ON "polar_event" USING btree ("polar_event_id");--> statement-breakpoint
CREATE UNIQUE INDEX "user_subscription_user_idx" ON "user_subscription" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "user_subscription_polar_customer_idx" ON "user_subscription" USING btree ("polar_customer_id");--> statement-breakpoint
CREATE UNIQUE INDEX "beta_waitlist_email_uniq" ON "beta_waitlist" USING btree ("email");--> statement-breakpoint
CREATE INDEX "beta_waitlist_created_idx" ON "beta_waitlist" USING btree ("created_at");