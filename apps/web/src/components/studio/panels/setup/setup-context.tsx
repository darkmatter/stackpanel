"use client";

import { createContext, useContext } from "react";
import type { SetupContextValue } from "./types";

const SetupContext = createContext<SetupContextValue | null>(null);

export function SetupProvider({
	children,
	value,
}: {
	children: React.ReactNode;
	value: SetupContextValue;
}) {
	return (
		<SetupContext.Provider value={value}>{children}</SetupContext.Provider>
	);
}

export function useSetupContext() {
	const context = useContext(SetupContext);
	if (!context) {
		throw new Error("useSetupContext must be used within SetupProvider");
	}
	return context;
}
