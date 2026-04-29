"use client";

import { Button } from "@ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@ui/dialog";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { Textarea } from "@ui/textarea";
import { useMutation } from "@tanstack/react-query";
import {
	ArrowRight,
	CheckCircle2,
	ExternalLink,
	Loader2,
	PlayCircle,
} from "lucide-react";
import {
	createContext,
	type ReactNode,
	useCallback,
	useContext,
	useMemo,
	useState,
} from "react";
import { Link } from "@tanstack/react-router";
import { toast } from "sonner";
import { useTRPC } from "@/utils/trpc";
import { cn } from "@/lib/utils";

type WaitlistOpenOptions = {
	source?: string;
	tier?: string;
};

type WaitlistContextValue = {
	open: (opts?: WaitlistOpenOptions) => void;
	close: () => void;
};

const WaitlistContext = createContext<WaitlistContextValue | null>(null);

/**
 * Provides a single global waitlist dialog mounted at the layout level.
 * Any descendant can call `useWaitlist().open({ source: "..." })` to
 * trigger it; only one instance is ever rendered.
 */
export function WaitlistProvider({ children }: { children: ReactNode }) {
	const [openState, setOpenState] = useState(false);
	const [source, setSource] = useState<string | undefined>();
	const [tier, setTier] = useState<string | undefined>();

	const open = useCallback((opts?: WaitlistOpenOptions) => {
		setSource(opts?.source);
		setTier(opts?.tier);
		setOpenState(true);
	}, []);

	const close = useCallback(() => setOpenState(false), []);

	const value = useMemo<WaitlistContextValue>(
		() => ({ open, close }),
		[open, close],
	);

	return (
		<WaitlistContext.Provider value={value}>
			{children}
			<WaitlistDialog
				open={openState}
				onOpenChange={setOpenState}
				source={source}
				tier={tier}
			/>
		</WaitlistContext.Provider>
	);
}

export function useWaitlist(): WaitlistContextValue {
	const ctx = useContext(WaitlistContext);
	if (!ctx) {
		throw new Error("useWaitlist must be used within a <WaitlistProvider>");
	}
	return ctx;
}

type WaitlistDialogProps = {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	source?: string;
	tier?: string;
};

function WaitlistDialog({
	open,
	onOpenChange,
	source,
	tier,
}: WaitlistDialogProps) {
	const trpc = useTRPC();
	const [email, setEmail] = useState("");
	const [name, setName] = useState("");
	const [company, setCompany] = useState("");
	const [notes, setNotes] = useState("");
	const [submitted, setSubmitted] = useState<null | {
		alreadyOnList: boolean;
	}>(null);

	const referrer =
		typeof document !== "undefined" ? document.referrer || undefined : undefined;

	const join = useMutation(
		trpc.waitlist.join.mutationOptions({
			onSuccess: (data) => {
				setSubmitted({ alreadyOnList: data.alreadyOnList });
				if (data.alreadyOnList) {
					toast.success("You're already on the list — we'll be in touch.");
				} else {
					toast.success("You're on the list. We'll send a beta invite soon.");
				}
			},
			onError: (err) => {
				toast.error(err.message ?? "Could not join the waitlist.");
			},
		}),
	);

	const reset = useCallback(() => {
		setEmail("");
		setName("");
		setCompany("");
		setNotes("");
		setSubmitted(null);
	}, []);

	const handleOpenChange = useCallback(
		(next: boolean) => {
			if (!next) {
				setTimeout(reset, 200);
			}
			onOpenChange(next);
		},
		[onOpenChange, reset],
	);

	const handleSubmit = useCallback(
		(event: React.FormEvent<HTMLFormElement>) => {
			event.preventDefault();
			if (!email.trim()) return;
			join.mutate({
				email: email.trim(),
				name: name.trim() || undefined,
				company: company.trim() || undefined,
				notes: notes.trim() || undefined,
				source: tier ? `${source ?? "unknown"}.${tier}` : source,
				referrer,
			});
		},
		[email, name, company, notes, source, tier, referrer, join],
	);

	const isPending = join.isPending;

	return (
		<Dialog open={open} onOpenChange={handleOpenChange}>
			<DialogContent className="sm:max-w-lg">
				{submitted ? (
					<SuccessState
						alreadyOnList={submitted.alreadyOnList}
						onClose={() => handleOpenChange(false)}
					/>
				) : (
					<form onSubmit={handleSubmit} className="space-y-5">
						<DialogHeader>
							<DialogTitle className="text-xl">
								Join the Stackpanel beta
							</DialogTitle>
							<DialogDescription className="text-sm">
								We're rolling out access in waves. Tell us a bit about what
								you're building and we'll send you an invite when there's a
								slot.
							</DialogDescription>
						</DialogHeader>

						<div className="space-y-3">
							<div className="space-y-1.5">
								<Label htmlFor="waitlist-email" className="text-xs">
									Work email
								</Label>
								<Input
									id="waitlist-email"
									type="email"
									required
									autoComplete="email"
									placeholder="you@company.com"
									value={email}
									onChange={(e) => setEmail(e.target.value)}
									disabled={isPending}
								/>
							</div>

							<div className="grid grid-cols-2 gap-3">
								<div className="space-y-1.5">
									<Label htmlFor="waitlist-name" className="text-xs">
										Name <span className="text-muted-foreground">(optional)</span>
									</Label>
									<Input
										id="waitlist-name"
										type="text"
										autoComplete="name"
										placeholder="Ada Lovelace"
										value={name}
										onChange={(e) => setName(e.target.value)}
										disabled={isPending}
									/>
								</div>
								<div className="space-y-1.5">
									<Label htmlFor="waitlist-company" className="text-xs">
										Company{" "}
										<span className="text-muted-foreground">(optional)</span>
									</Label>
									<Input
										id="waitlist-company"
										type="text"
										autoComplete="organization"
										placeholder="Acme, Inc."
										value={company}
										onChange={(e) => setCompany(e.target.value)}
										disabled={isPending}
									/>
								</div>
							</div>

							<div className="space-y-1.5">
								<Label htmlFor="waitlist-notes" className="text-xs">
									What would you build with Stackpanel?{" "}
									<span className="text-muted-foreground">(optional)</span>
								</Label>
								<Textarea
									id="waitlist-notes"
									rows={3}
									placeholder="e.g. multi-tenant Next.js app on Cloudflare with a Postgres + Redis dev stack."
									value={notes}
									onChange={(e) => setNotes(e.target.value)}
									disabled={isPending}
								/>
							</div>
						</div>

						<p className="text-xs text-muted-foreground">
							Want to see what you're signing up for?{" "}
							<Link
								to="/demo"
								className="text-primary underline-offset-4 hover:underline"
								onClick={() => handleOpenChange(false)}
							>
								Open the live demo
							</Link>
							.
						</p>

						<DialogFooter className="gap-2 sm:gap-2">
							<Button
								type="button"
								variant="ghost"
								onClick={() => handleOpenChange(false)}
								disabled={isPending}
							>
								Cancel
							</Button>
							<Button
								type="submit"
								disabled={isPending || !email.trim()}
								className={cn("min-w-32")}
							>
								{isPending ? (
									<>
										<Loader2 className="mr-2 h-4 w-4 animate-spin" />
										Sending…
									</>
								) : (
									<>
										Join waitlist
										<ArrowRight className="ml-2 h-4 w-4" />
									</>
								)}
							</Button>
						</DialogFooter>
					</form>
				)}
			</DialogContent>
		</Dialog>
	);
}

function SuccessState({
	alreadyOnList,
	onClose,
}: {
	alreadyOnList: boolean;
	onClose: () => void;
}) {
	return (
		<div className="space-y-5">
			<DialogHeader>
				<div className="flex items-center justify-center mb-3">
					<div className="rounded-full bg-primary/10 p-3">
						<CheckCircle2 className="h-7 w-7 text-primary" />
					</div>
				</div>
				<DialogTitle className="text-center text-xl">
					{alreadyOnList ? "You're already on the list" : "You're on the list"}
				</DialogTitle>
				<DialogDescription className="text-center text-sm">
					{alreadyOnList
						? "We've got your earlier signup. Sit tight — we'll reach out when there's a slot."
						: "We'll email you the moment your beta invite is ready. In the meantime, click around the live demo so you know what's coming."}
				</DialogDescription>
			</DialogHeader>

			<div className="grid gap-2 sm:grid-cols-2">
				<Button asChild variant="default">
					<Link to="/demo" onClick={onClose}>
						<PlayCircle className="mr-2 h-4 w-4" />
						Try the demo Studio
					</Link>
				</Button>
				<Button asChild variant="outline">
					<a
						href="https://github.com/darkmatter/stackpanel"
						target="_blank"
						rel="noreferrer noopener"
						onClick={onClose}
					>
						<ExternalLink className="mr-2 h-4 w-4" />
						Star us on GitHub
					</a>
				</Button>
			</div>

			<p className="text-center text-xs text-muted-foreground">
				No spam. We'll only email you about the beta.
			</p>
		</div>
	);
}
