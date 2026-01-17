"use client";

import { guides } from "@stackpanel/docs-content";
import { GuideDialog } from "../shared/guide-dialog";

export function VariablesGuideDialog() {
	return <GuideDialog guide={guides.variables} />;
}
