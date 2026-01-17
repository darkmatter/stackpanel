import { Button } from "@ui/button";
import { Bell, ChevronRight, Settings } from "lucide-react";

interface AppHeaderProps {
	title: string;
	subtitle?: string;
	stats?: string;
}

export function AppHeader({ title, subtitle, stats }: AppHeaderProps) {
	return (
		<header className="border-b border-border px-6 py-3 flex items-center justify-between">
			<div className="flex items-center gap-4">
				<Button variant="ghost" size="sm" className="gap-2">
					<ChevronRight className="h-4 w-4" />
					<span className="text-sm text-muted-foreground">Exit Demo</span>
				</Button>
				<div>
					<h1 className="text-xl font-semibold">{title}</h1>
					{subtitle && (
						<p className="text-xs text-muted-foreground">{subtitle}</p>
					)}
				</div>
			</div>

			<div className="flex items-center gap-3">
				{stats && <div className="text-sm text-muted-foreground">{stats}</div>}
				<Button variant="ghost" size="icon" className="h-8 w-8">
					<Bell className="h-4 w-4" />
				</Button>
				<Button variant="ghost" size="icon" className="h-8 w-8">
					<Settings className="h-4 w-4" />
				</Button>
				<div className="flex items-center gap-2">
					<div className="h-2 w-2 rounded-full bg-green-500" />
					<span className="text-sm text-muted-foreground">Connected</span>
				</div>
				<div className="h-8 w-8 rounded-full bg-green-500 flex items-center justify-center text-xs font-medium text-primary-foreground">
					JD
				</div>
			</div>
		</header>
	);
}
