/**
 * Constants and helper functions for the team panel.
 */

export function getRoleColor(role: string): string {
	switch (role) {
		case "Admin":
			return "bg-purple-500/10 text-purple-400 border-purple-500/20";
		case "Member":
			return "bg-accent/10 text-accent border-accent/20";
		case "Write":
			return "bg-blue-500/10 text-blue-400 border-blue-500/20";
		case "Read":
			return "bg-slate-500/10 text-slate-400 border-slate-500/20";
		case "Maintain":
			return "bg-green-500/10 text-green-400 border-green-500/20";
		case "Triage":
			return "bg-yellow-500/10 text-yellow-400 border-yellow-500/20";
		default:
			return "";
	}
}
