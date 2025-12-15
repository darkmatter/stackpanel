import { env } from "cloudflare:workers";
import { neonConfig } from "@neondatabase/serverless";
import { PrismaNeon } from "@prisma/adapter-neon";
import { PrismaClient } from "../prisma/generated/client";

neonConfig.poolQueryViaFetch = true;

const prisma = new PrismaClient({
	adapter: new PrismaNeon({
		connectionString: env.DATABASE_URL || "",
	}),
});

export default prisma;
