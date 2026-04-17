import { cleanup } from "@testing-library/react";
import { afterEach, vi } from "vite-plus/test";

// Cleanup after each test case (e.g., clearing jsdom)
afterEach(() => {
	cleanup();
});

// Mock fetch globally for tests
global.fetch = vi.fn() as unknown as typeof fetch;

// Mock localStorage
const localStorageMock = {
	getItem: vi.fn(),
	setItem: vi.fn(),
	removeItem: vi.fn(),
	clear: vi.fn(),
	length: 0,
	key: vi.fn(),
};
global.localStorage = localStorageMock as Storage;

// Mock WebSocket
class MockWebSocket {
	static CONNECTING = 0;
	static OPEN = 1;
	static CLOSING = 2;
	static CLOSED = 3;

	readyState = MockWebSocket.CONNECTING;
	onopen: ((event: Event) => void) | null = null;
	onclose: ((event: CloseEvent) => void) | null = null;
	onerror: ((event: Event) => void) | null = null;
	onmessage: ((event: MessageEvent) => void) | null = null;

	constructor(public url: string) {}

	send = vi.fn();
	close = vi.fn();
}

global.WebSocket = MockWebSocket as unknown as typeof WebSocket;

// Helper to reset all mocks between tests
afterEach(() => {
	vi.clearAllMocks();
});
