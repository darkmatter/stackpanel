/**
 * Type definitions for the team panel.
 */
import type { User } from "@/lib/types";

export type { User };

export type GithubCollaborator = {
	login: string;
	role: string;
	isAdmin?: boolean;
	publicKeys?: string[];
};

export type GithubCollaboratorsData = {
	_meta?: { source?: string; generatedAt?: string };
	collaborators?: Record<string, GithubCollaborator>;
};

export type TeamMember = {
	id: string;
	name: string;
	handle: string | null;
	role: string;
	status: "active" | "pending";
	publicKeys: string[];
	secretsAccess: string[];
	source: "stackpanel" | "github";
};
