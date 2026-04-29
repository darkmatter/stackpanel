import { Link } from "@tanstack/react-router";
import { Github, Twitter } from "lucide-react";

type LinkGroup = {
	label: string;
	items: Array<{ label: string; href: string; external?: boolean }>;
};

const linkGroups: LinkGroup[] = [
	{
		label: "Product",
		items: [
			{ label: "Features", href: "/#features" },
			{ label: "How it works", href: "/#how-it-works" },
			{ label: "Production Stacks", href: "/#stacks" },
			{ label: "Pricing", href: "/pricing" },
			{ label: "Studio", href: "/studio" },
		],
	},
	{
		label: "Resources",
		items: [
			{ label: "Documentation", href: "/docs" },
			{ label: "Quick start", href: "/docs/quick-start" },
			{ label: "Why Stackpanel", href: "/docs/why" },
			{ label: "Changelog", href: "/docs/changelog" },
		],
	},
	{
		label: "Open source",
		items: [
			{
				label: "GitHub",
				href: "https://github.com/darkmatter/stackpanel",
				external: true,
			},
			{
				label: "Issues",
				href: "https://github.com/darkmatter/stackpanel/issues",
				external: true,
			},
			{
				label: "Discussions",
				href: "https://github.com/darkmatter/stackpanel/discussions",
				external: true,
			},
			{
				label: "Releases",
				href: "https://github.com/darkmatter/stackpanel/releases",
				external: true,
			},
		],
	},
	{
		label: "Legal",
		items: [
			{ label: "Privacy", href: "/privacy" },
			{ label: "Terms", href: "/terms" },
			{ label: "Security", href: "/security" },
			{ label: "License (MIT)", href: "/docs/license" },
		],
	},
];

export function Footer() {
	return (
		<footer className="border-border border-t bg-secondary/20">
			<div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8 lg:py-16">
				<div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-6">
					<div className="lg:col-span-2">
						<Link className="flex items-center gap-2.5" to="/">
							<div className="flex h-8 w-8 items-center justify-center rounded-lg bg-accent">
								<span className="font-bold font-[Montserrat] text-accent-foreground text-sm">
									S
								</span>
							</div>
							<span className="font-semibold font-[Montserrat] text-foreground text-lg">
								Stackpanel
							</span>
						</Link>
						<p className="mt-4 max-w-xs text-muted-foreground text-sm leading-relaxed">
							The open-source dev platform that turns one Nix config into a
							reproducible environment, encrypted secrets, real HTTPS, and a
							studio for everything else.
						</p>
						<div className="mt-5 flex items-center gap-3">
							<a
								className="rounded-md border border-border p-2 text-muted-foreground transition-colors hover:border-accent/40 hover:text-foreground"
								href="https://github.com/darkmatter/stackpanel"
								rel="noopener noreferrer"
								target="_blank"
							>
								<Github className="h-4 w-4" />
								<span className="sr-only">GitHub</span>
							</a>
							<a
								className="rounded-md border border-border p-2 text-muted-foreground transition-colors hover:border-accent/40 hover:text-foreground"
								href="https://twitter.com/stackpanel_dev"
								rel="noopener noreferrer"
								target="_blank"
							>
								<Twitter className="h-4 w-4" />
								<span className="sr-only">Twitter</span>
							</a>
						</div>
					</div>

					{linkGroups.map((group) => (
						<div key={group.label}>
							<h3 className="font-semibold text-foreground text-sm">
								{group.label}
							</h3>
							<ul className="mt-4 space-y-3">
								{group.items.map((item) => (
									<li key={item.label}>
										{item.external ? (
											<a
												className="text-muted-foreground text-sm transition-colors hover:text-foreground"
												href={item.href}
												rel="noopener noreferrer"
												target="_blank"
											>
												{item.label}
											</a>
										) : (
											<a
												className="text-muted-foreground text-sm transition-colors hover:text-foreground"
												href={item.href}
											>
												{item.label}
											</a>
										)}
									</li>
								))}
							</ul>
						</div>
					))}
				</div>

				<div className="mt-12 flex flex-col items-center justify-between gap-3 border-border border-t pt-8 sm:flex-row">
					<p className="text-muted-foreground text-xs">
						© {new Date().getFullYear()} Stackpanel · MIT licensed · Built on
						Nix, devenv, Caddy, SOPS, and process-compose
					</p>
					<p className="text-muted-foreground text-xs">
						Not affiliated with NixOS, devenv, or Cloudflare.
					</p>
				</div>
			</div>
		</footer>
	);
}
