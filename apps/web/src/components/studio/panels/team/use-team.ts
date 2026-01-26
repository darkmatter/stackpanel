/**
 * Hook for managing team panel state.
 */
import { useMemo, useState } from "react";
import type { User } from "@/lib/types";
import { useNixData } from "@/lib/use-agent";
import type { GithubCollaboratorsData, TeamMember } from "./types";

/** 
 * Type alias for User from Nix data.
 * The proto User type now includes public_keys and secrets_allowed_environments.
 */
type NixUser = User;

export function useTeam() {
	const [searchQuery, setSearchQuery] = useState("");
	const [dialogOpen, setDialogOpen] = useState(false);

	const { data: usersData, isLoading: usersLoading } =
		useNixData<Record<string, NixUser>>("users");
	const { data: githubData, isLoading: githubLoading } =
		useNixData<GithubCollaboratorsData>("external-github-collaborators");

	const members = useMemo<TeamMember[]>(() => {
		const users = usersData ?? {};
		const collaborators = githubData?.collaborators ?? {};
		const entries: TeamMember[] = [];
		const githubHandles = new Set(
			Object.values(users)
				.map((user) => user.github?.toLowerCase())
				.filter((handle): handle is string => Boolean(handle)),
		);

		for (const [key, user] of Object.entries(users)) {
			const displayName = user.name || user.github || key;
			const handle = user.github ? `@${user.github}` : null;
			const publicKeys = user.public_keys ?? [];
		const secretsAccess = (user.secrets_allowed_environments ?? []).map(
			(env: string) => String(env).toLowerCase(),
		);

			entries.push({
				id: key,
				name: displayName,
				handle,
				role: "Member",
				status: publicKeys.length > 0 ? "active" : "pending",
				publicKeys,
				secretsAccess,
				source: "stackpanel",
			});
		}

		for (const [key, collaborator] of Object.entries(collaborators)) {
			if (githubHandles.has(collaborator.login.toLowerCase())) {
				continue;
			}
			const publicKeys = collaborator.publicKeys ?? [];
			const roleValue = collaborator.role ?? "member";
			const roleLabel = collaborator.isAdmin
				? "Admin"
				: roleValue.charAt(0).toUpperCase() + roleValue.slice(1);

			entries.push({
				id: key,
				name: collaborator.login,
				handle: `@${collaborator.login}`,
				role: roleLabel,
				status: publicKeys.length > 0 ? "active" : "pending",
				publicKeys,
				secretsAccess: [],
				source: "github",
			});
		}

		return entries.sort((a, b) => a.name.localeCompare(b.name));
	}, [usersData, githubData]);

	const filteredMembers = useMemo(() => {
		const query = searchQuery.trim().toLowerCase();
		if (!query) return members;
		return members.filter(
			(member) =>
				member.name.toLowerCase().includes(query) ||
				member.handle?.toLowerCase().includes(query) ||
				member.role.toLowerCase().includes(query),
		);
	}, [members, searchQuery]);

	const totalMembers = members.length;
	const keysRegistered = members.filter(
		(member) => member.publicKeys.length > 0,
	).length;
	const adminCount = members.filter((member) => member.role === "Admin").length;

	const isLoading = usersLoading || githubLoading;

	return {
		// UI state
		searchQuery,
		setSearchQuery,
		dialogOpen,
		setDialogOpen,

		// Data
		members,
		filteredMembers,
		isLoading,

		// Stats
		totalMembers,
		keysRegistered,
		adminCount,
	};
}
