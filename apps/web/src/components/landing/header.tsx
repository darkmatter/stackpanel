"use client";

import { Logo } from "@stackpanel/ui-core/logo";
import { Link } from "@tanstack/react-router";
import { Menu, X } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";

export function Header() {
	const [isMenuOpen, setIsMenuOpen] = useState(false);

	return (
		<header className="sticky top-0 z-50 border-border border-b bg-background/80 backdrop-blur-xl">
			<div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
				<div className="flex items-center gap-8">
					<Link className="flex items-center gap-2" to="/">
						{/* <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-accent">
              <span className="font-bold text-accent-foreground text-sm">
								SP
							</span>
            </div> */}
						{/* <span className="font-semibold text-foreground text-lg">
							StackPanel
						</span> */}
						<Logo className="max-w-32" />
					</Link>

					<nav className="hidden items-center gap-6 md:flex">
						<a
							className="text-muted-foreground text-sm transition-colors hover:text-foreground"
							href="#features"
						>
							Features
						</a>
						<a
							className="text-muted-foreground text-sm transition-colors hover:text-foreground"
							href="#infrastructure"
						>
							Infrastructure
						</a>
						<a
							className="text-muted-foreground text-sm transition-colors hover:text-foreground"
							href="#devex"
						>
							DevEx
						</a>
						<a
							className="text-muted-foreground text-sm transition-colors hover:text-foreground"
							href="#pricing"
						>
							Pricing
						</a>
						<a
							className="text-muted-foreground text-sm transition-colors hover:text-foreground"
							href="#docs"
						>
							Docs
						</a>
					</nav>
				</div>

				<div className="hidden items-center gap-4 md:flex">
					<Button asChild size="sm" variant="ghost">
						<Link to="/login">Sign In</Link>
					</Button>
					<Button
						asChild
						className="bg-foreground text-background hover:bg-foreground/90"
						size="sm"
					>
						<Link to="/login">Get Started</Link>
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
					<nav className="flex flex-col gap-4 px-4 py-6">
						<a
							className="text-muted-foreground text-sm transition-colors hover:text-foreground"
							href="#features"
						>
							Features
						</a>
						<a
							className="text-muted-foreground text-sm transition-colors hover:text-foreground"
							href="#infrastructure"
						>
							Infrastructure
						</a>
						<a
							className="text-muted-foreground text-sm transition-colors hover:text-foreground"
							href="#devex"
						>
							DevEx
						</a>
						<a
							className="text-muted-foreground text-sm transition-colors hover:text-foreground"
							href="#pricing"
						>
							Pricing
						</a>
						<a
							className="text-muted-foreground text-sm transition-colors hover:text-foreground"
							href="#docs"
						>
							Docs
						</a>
						<div className="flex flex-col gap-2 pt-4">
							<Button
								asChild
								className="justify-start"
								size="sm"
								variant="ghost"
							>
								<Link to="/login">Sign In</Link>
							</Button>
							<Button
								asChild
								className="bg-foreground text-background hover:bg-foreground/90"
								size="sm"
							>
								<Link to="/login">Get Started</Link>
							</Button>
						</div>
					</nav>
				</div>
			)}
		</header>
	);
}
