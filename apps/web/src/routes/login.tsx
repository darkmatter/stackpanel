import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import SignInForm from "@/components/sign-in-form";
import SignUpForm from "@/components/sign-up-form";
import { authClient } from "@/lib/auth-client";
import Loader from "@/components/loader";

export const Route = createFileRoute("/login")({
	component: LoginPage,
});

function LoginPage() {
	const [isSignIn, setIsSignIn] = useState(true);
	const { data: session, isPending } = authClient.useSession();
	const navigate = useNavigate();

	// If already logged in, redirect to dashboard
	if (session?.user) {
		navigate({ to: "/dashboard" });
		return null;
	}

	if (isPending) {
		return (
			<div className="flex min-h-screen items-center justify-center">
				<Loader />
			</div>
		);
	}

	return (
		<div className="flex min-h-screen flex-col items-center justify-center bg-background">
			{isSignIn ? (
				<SignInForm onSwitchToSignUp={() => setIsSignIn(false)} />
			) : (
				<SignUpForm onSwitchToSignIn={() => setIsSignIn(true)} />
			)}
		</div>
	);
}
