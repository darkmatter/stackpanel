/**
 * State management hook for Network Panel
 */

import { useCallback, useMemo, useState } from "react";
import { useNixConfig, useNixData } from "@/lib/use-agent";
import type {
	StepCaData,
	DnsData,
	CertificateItem,
	ProcessedDnsRecord,
} from "./types";

export function useNetwork() {
	const { data: config } = useNixConfig();
	const { data: stepCaData, mutate: setStepCa } =
		useNixData<StepCaData>("step-ca");
	const { data: dnsData } = useNixData<DnsData>("dns");
	const [isEnabling, setIsEnabling] = useState(false);

	// Type-safe access to optional config properties
	const stepCaConfig = config as { stepCa?: { "step-ca"?: { enable?: boolean; "ca-url"?: string; "ca-fingerprint"?: string; "cert-name"?: string } } } | null;
	const awsConfig = config as { aws?: { "roles-anywhere"?: { enable?: boolean; "role-name"?: string; "profile-arn"?: string } } } | null;

	const stepConfig = stepCaConfig?.stepCa?.["step-ca"];
	const stepEnabled = stepConfig?.enable ?? stepCaData?.enable ?? false;
	const caUrl = stepConfig?.["ca-url"] ?? stepCaData?.ca_url ?? null;
	const caFingerprint =
		stepConfig?.["ca-fingerprint"] ?? stepCaData?.ca_fingerprint ?? null;
	const certName = stepConfig?.["cert-name"] ?? stepCaData?.cert_name;
	const awsRolesAnywhere = awsConfig?.aws?.["roles-anywhere"];

	const certificates = useMemo<CertificateItem[]>(() => {
		const items: CertificateItem[] = [];

		if (stepEnabled) {
			items.push({
				name: certName ?? "Device certificate",
				type: "Step CA",
				detail: caUrl ? `CA: ${caUrl}` : "Managed by Step CA",
			});
		}

		if (awsRolesAnywhere?.enable) {
			items.push({
				name: awsRolesAnywhere["role-name"] ?? "AWS Roles Anywhere",
				type: "AWS Roles Anywhere",
				detail: awsRolesAnywhere["profile-arn"]
					? `Profile: ${awsRolesAnywhere["profile-arn"]}`
					: "Certificate auth enabled",
			});
		}

		return items;
	}, [awsRolesAnywhere, caUrl, certName, stepEnabled]);

	const dnsRecords = useMemo<ProcessedDnsRecord[]>(() => {
		const zones = dnsData?.zones ?? {};
		return Object.values(zones).flatMap((zone) => {
			const domain = zone.domain ?? "";
			return (zone.records ?? []).map((record) => {
				const host =
					record.name && record.name !== "@"
						? `${record.name}.${domain}`
						: domain;
				return {
					domain: host || domain,
					target: record.value ?? "",
					type: record.type ?? "",
					comment: record.comment ?? "",
				};
			});
		});
	}, [dnsData]);

	const dnsZoneLabel = useMemo(() => {
		const zones = Object.values(dnsData?.zones ?? {});
		return zones[0]?.domain ?? null;
	}, [dnsData]);

	const handleEnableStepCa = useCallback(async () => {
		if (isEnabling) return;
		setIsEnabling(true);
		try {
			await setStepCa({
				...(stepCaData ?? {}),
				enable: true,
			});
		} finally {
			setIsEnabling(false);
		}
	}, [isEnabling, setStepCa, stepCaData]);

	return {
		stepEnabled,
		caUrl,
		caFingerprint,
		certificates,
		dnsRecords,
		dnsZoneLabel,
		isEnabling,
		handleEnableStepCa,
	};
}
