import { PrismaClient } from "../prisma/generated/client";
import { env } from "cloudflare:workers";
import { PrismaNeon } from "@prisma/adapter-neon";
import { neonConfig } from "@neondatabase/serverless";

neonConfig.poolQueryViaFetch = true;

const prisma = new PrismaClient({
	adapter: new PrismaNeon({
		connectionString: env.DATABASE_URL || "",
	}),
});

export default prisma;
