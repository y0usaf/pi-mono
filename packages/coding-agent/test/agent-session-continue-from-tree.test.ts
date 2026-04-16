import type { AgentTool } from "@mariozechner/pi-agent-core";
import { fauxAssistantMessage, fauxToolCall } from "@mariozechner/pi-ai";
import { Type } from "@sinclair/typebox";
import { afterEach, describe, expect, it } from "vitest";
import { createHarness, getMessageText, type Harness } from "./suite/harness.js";

describe("AgentSession continueFromTree", () => {
	const harnesses: Harness[] = [];

	afterEach(() => {
		while (harnesses.length > 0) {
			harnesses.pop()?.cleanup();
		}
	});

	it("continues from a prior user checkpoint without duplicating the user message", async () => {
		const harness = await createHarness();
		harnesses.push(harness);
		harness.setResponses([
			fauxAssistantMessage("first reply"),
			fauxAssistantMessage("second reply"),
			fauxAssistantMessage("retried first reply"),
		]);

		await harness.session.prompt("first");
		await harness.session.prompt("second");

		const entries = harness.sessionManager.getEntries();
		const firstUserEntry = entries.find((entry) => entry.type === "message" && entry.message.role === "user");
		expect(firstUserEntry).toBeDefined();

		const result = await harness.session.continueFromTree(firstUserEntry!.id);

		expect(result.cancelled).toBe(false);
		expect(harness.faux.state.callCount).toBe(3);
		expect(entries.filter((entry) => entry.type === "message" && entry.message.role === "user")).toHaveLength(2);

		const branch = harness.sessionManager.getBranch();
		const branchUserTexts = branch
			.filter((entry): entry is Extract<(typeof branch)[number], { type: "message" }> => entry.type === "message")
			.filter((entry) => entry.message.role === "user")
			.map((entry) => getMessageText(entry.message));
		expect(branchUserTexts).toEqual(["first"]);

		const branchAssistantTexts = branch
			.filter((entry): entry is Extract<(typeof branch)[number], { type: "message" }> => entry.type === "message")
			.filter((entry) => entry.message.role === "assistant")
			.map((entry) => getMessageText(entry.message));
		expect(branchAssistantTexts[branchAssistantTexts.length - 1]).toBe("retried first reply");
	});

	it("continues from a tool-result checkpoint without rerunning the tool", async () => {
		const toolRuns: string[] = [];
		const echoTool: AgentTool = {
			name: "echo",
			label: "Echo",
			description: "Echo text back",
			parameters: Type.Object({ text: Type.String() }),
			execute: async (_toolCallId, params) => {
				const text = typeof params === "object" && params !== null && "text" in params ? String(params.text) : "";
				toolRuns.push(text);
				return { content: [{ type: "text", text: `echo:${text}` }], details: { text } };
			},
		};
		const harness = await createHarness({ tools: [echoTool] });
		harnesses.push(harness);
		harness.setResponses([
			fauxAssistantMessage([fauxToolCall("echo", { text: "hello" })], { stopReason: "toolUse" }),
			fauxAssistantMessage("after tool"),
			fauxAssistantMessage("retry from tool result"),
		]);

		await harness.session.prompt("hi");
		expect(toolRuns).toEqual(["hello"]);

		const toolResultEntry = harness.sessionManager
			.getEntries()
			.slice()
			.reverse()
			.find((entry) => entry.type === "message" && entry.message.role === "toolResult");
		expect(toolResultEntry).toBeDefined();

		const result = await harness.session.continueFromTree(toolResultEntry!.id);

		expect(result.cancelled).toBe(false);
		expect(harness.faux.state.callCount).toBe(3);
		expect(toolRuns).toEqual(["hello"]);
		expect(
			harness.sessionManager
				.getEntries()
				.filter((entry) => entry.type === "message" && entry.message.role === "user"),
		).toHaveLength(1);

		const branch = harness.sessionManager.getBranch();
		const branchToolResults = branch
			.filter((entry): entry is Extract<(typeof branch)[number], { type: "message" }> => entry.type === "message")
			.filter((entry) => entry.message.role === "toolResult");
		expect(branchToolResults).toHaveLength(1);

		const branchAssistantTexts = branch
			.filter((entry): entry is Extract<(typeof branch)[number], { type: "message" }> => entry.type === "message")
			.filter((entry) => entry.message.role === "assistant")
			.map((entry) => getMessageText(entry.message));
		expect(branchAssistantTexts[branchAssistantTexts.length - 1]).toBe("retry from tool result");
	});
});
