/**
 * Constants and mock data for Network Panel
 */

import type { TailscaleDevice } from "./types";

export const MOCK_TAILSCALE_DEVICES: TailscaleDevice[] = [
	{
		name: "janes-macbook",
		type: "laptop",
		ip: "100.64.0.1",
		status: "online",
		os: "macOS",
	},
	{
		name: "mikes-workstation",
		type: "laptop",
		ip: "100.64.0.2",
		status: "online",
		os: "Linux",
	},
	{
		name: "api-gateway-1",
		type: "server",
		ip: "100.64.0.10",
		status: "online",
		os: "Linux",
	},
	{
		name: "api-gateway-2",
		type: "server",
		ip: "100.64.0.11",
		status: "online",
		os: "Linux",
	},
	{
		name: "db-primary",
		type: "server",
		ip: "100.64.0.20",
		status: "online",
		os: "Linux",
	},
	{
		name: "sarahs-iphone",
		type: "phone",
		ip: "100.64.0.3",
		status: "offline",
		os: "iOS",
	},
];
