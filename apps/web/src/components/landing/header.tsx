"use client";

import { Logo } from "@stackpanel/ui-core/logo";
import { Link } from "@tanstack/react-router";
import { Button } from "@ui/button";
import { Github, Menu, X } from "lucide-react";
import { useState } from "react";
import { useWaitlist } from "./waitlist-dialog";

const navItems = [
	{ label: "How it works", href: "/#how-it-works" },
	{ label: "Features", href: "/#features" },
	{ label: "Stacks", href: "/#stacks" },
	{ label: "Pricing", href: "/pricing" },
	{ label: "Compare", href: "/#compare" },
	{ label: "Demo", href: "/demo" },
	{ label: "Docs", href: "/docs" },
];

export function Header() {
	const [isMenuOpen, setIsMenuOpen] = useState(false);
	const waitlist = useWaitlist();

	return (
		<header className="sticky top-0 z-50 border-border border-b bg-background/80 backdrop-blur-xl">
			<div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
				<div className="flex items-center gap-8">
					<Link className="flex items-center gap-2" to="/">
						<Logo className="max-w-32" />
					</Link>

					<nav className="hidden items-center gap-6 md:flex">
						{navItems.map((item) => (
							<a
								className="text-muted-foreground text-sm transition-colors hover:text-foreground"
								href={item.href}
								key={item.href}
							>
								{item.label}
							</a>
						))}
					</nav>
				</div>

				<div className="hidden items-center gap-2 md:flex">
					<Button
						asChild
						className="text-muted-foreground hover:text-foreground"
						size="sm"
						variant="ghost"
					>
						<a
							aria-label="GitHub"
							href="https://github.com/darkmatter/stackpanel"
							rel="noopener noreferrer"
							target="_blank"
						>
							<Github className="h-4 w-4" />
						</a>
					</Button>
					<Button asChild size="sm" variant="ghost">
						<Link to="/login">Sign in</Link>
					</Button>
					<Button
						className="bg-foreground text-background hover:bg-foreground/90"
						size="sm"
						onClick={() => waitlist.open({ source: "header" })}
					>
						Join the beta
					</Button>
				</div>

				<button
					aria-label="Toggle menu"
					className="md:hidden"
					onClick={() => setIsMenuOpen(!isMenuOpen)}
					type="button"
				>
					{isMenuOpen ? (
						<X className="h-6 w-6" />
					) : (
						<Menu className="h-6 w-6" />
					)}
				</button>
			</div>

			{isMenuOpen && (
				<div className="border-border border-t bg-background md:hidden">
					<nav className="flex flex-col gap-1 px-4 py-4">
						{navItems.map((item) => (
							<a
								className="rounded-md px-2 py-2 text-muted-foreground text-sm transition-colors hover:bg-secondary hover:text-foreground"
								href={item.href}
								key={item.href}
								onClick={() => setIsMenuOpen(false)}
							>
								{item.label}
							</a>
						))}
						<div className="mt-3 flex flex-col gap-2 border-border/60 border-t pt-3">
							<Button
								asChild
								className="justify-start"
								size="sm"
								variant="ghost"
							>
								<a
									href="https://github.com/darkmatter/stackpanel"
									rel="noopener noreferrer"
									target="_blank"
								>
									<Github className="mr-2 h-4 w-4" />
									GitHub
								</a>
							</Button>
							<Button
								asChild
								className="justify-start"
								size="sm"
								variant="ghost"
							>
								<Link to="/login">Sign in</Link>
							</Button>
							<Button
								className="bg-foreground text-background hover:bg-foreground/90"
								size="sm"
								onClick={() => {
									setIsMenuOpen(false);
									waitlist.open({ source: "header.mobile" });
								}}
							>
								Join the beta
							</Button>
						</div>
					</nav>
				</div>
			)}
		</header>
	);
}
