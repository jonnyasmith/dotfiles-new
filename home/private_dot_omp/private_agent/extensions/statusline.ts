import { SEGMENTS, theme, type ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

/** `_A` in core: 59000 -> "59K", 1048576 -> "1M". */
function compact(n: number): string {
	if (!Number.isFinite(n) || n < 1000) return String(Math.max(0, Math.round(n || 0)));
	const trim = (v: number) => {
		const s = v.toFixed(1);
		return s.endsWith(".0") ? s.slice(0, -2) : s;
	};
	if (n < 1e4) return `${trim(n / 1000)}K`;
	if (n < 1e6) return `${Math.round(n / 1000)}K`;
	if (n < 1e7) return `${trim(n / 1e6)}M`;
	return `${Math.round(n / 1e6)}M`;
}

/** Core thresholds: percent-or-absolute, whichever trips first. */
function level(percent: number, window: number): "error" | "thinkingHigh" | "warning" | "statusLineContext" {
	const trips = (pct: number, abs: number) =>
		window > 0 ? percent >= Math.min(pct, (abs / window) * 100) : percent >= pct;
	if (trips(90, 500_000)) return "error";
	if (trips(70, 270_000)) return "thinkingHigh";
	if (trips(50, 150_000)) return "warning";
	return "statusLineContext";
}

export default function (pi: ExtensionAPI) {
	pi.setLabel("statusline");

	// Replace the built-in `context_pct` in place: keeping the id means the status
	// line still computes context usage for us (it is skipped unless a configured
	// segment id is `context_pct` or `context_total`).
	SEGMENTS.context_pct = {
		id: "context_pct",
		render(ctx) {
			const window = ctx.contextWindow;
			const used = ctx.contextTokens ?? 0;
			const percent = ctx.contextPercent;
			// Tokens used is the number you act on; the window size is a constant
			// you already know from the model name.
			const parts = [theme.fg(level(percent ?? 0, window), compact(used))];
			if (percent !== null && percent !== undefined) {
				parts.push(theme.fg("dim", `(${Math.round(percent)}%)`));
			}
			if (theme.icon.context) parts.unshift(theme.icon.context);
			return { content: parts.join(" "), visible: true };
		},
	};

	pi.on("session_start", async (_event, ctx) => {
		// The status line only re-renders on activity, so a refresh that lands
		// while the session is idle would sit invisible until the next keypress.
		// Deleting an unset hook-status key is a no-op that requests a repaint.
		if (ctx.hasUI) repaint = () => ctx.ui.setStatus("quota:repaint", undefined);
		const timer = ctx.setInterval(() => refresh(), REFRESH_MS);
		pi.on("session_shutdown", () => ctx.clearTimer(timer));
	});
}

// ---------------------------------------------------------------------------
// `quota`: the active provider's 5h/7d subscription windows. The built-in
// `usage` segment covers the same ground but renders nothing until its report
// arrives and never shows reset wall-clocks.
// ---------------------------------------------------------------------------

type Window = { percent: number; resetsAt?: number; tiered: boolean };
type Row = { provider: string; label: string; fiveHour?: Window; sevenDay?: Window };

const LABELS: Record<string, string> = {
	anthropic: "claude",
	"openai-codex": "codex",
	openai: "openai",
	google: "gemini",
	"google-antigravity": "antigravity",
};

type UsageSession = { fetchUsageReports?: (signal?: AbortSignal) => Promise<unknown> };

const REFRESH_MS = 120_000;
let rows: Row[] = [];
let fetchedAt = 0;
let inflight = false;
let repaint: (() => void) | null = null;
let liveSession: UsageSession | null = null;

/** Core's `r9`: usedFraction, else used/limit, else percent, else 1-remaining. */
function usedFraction(amount: Record<string, number | string | undefined> | undefined): number | undefined {
	if (!amount) return undefined;
	const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
	const used = num(amount.used);
	const limit = num(amount.limit);
	const fraction = num(amount.usedFraction);
	if (fraction !== undefined) return fraction;
	if (used !== undefined && limit !== undefined && limit > 0) return used / limit;
	if (amount.unit === "percent" && used !== undefined) return used / 100;
	const remaining = num(amount.remainingFraction);
	if (remaining !== undefined) return Math.max(0, 1 - remaining);
	return undefined;
}

function parse(reports: unknown): Row[] {
	if (!Array.isArray(reports)) return [];
	const byProvider = new Map<string, Row>();
	for (const report of reports) {
		const provider = report?.provider;
		if (typeof provider !== "string" || !Array.isArray(report.limits)) continue;
		const row = byProvider.get(provider) ?? {
			provider,
			label: LABELS[provider] ?? provider,
		};
		for (const limit of report.limits) {
			const fraction = usedFraction(limit?.amount);
			if (fraction === undefined) continue;
			const id = limit.window?.id ?? limit.scope?.windowId;
			const key = id === "5h" ? "fiveHour" : id === "7d" ? "sevenDay" : undefined;
			if (!key) continue;
			const percent = fraction * 100;
			// Providers report per-tier sub-buckets beside the account-wide window
			// (`7 days (Spark)`, `Claude 7 Day (Fable)`). The untiered one is the
			// real budget; only fall back to a tiered figure if that is all we get.
			const tiered = Boolean(limit.scope?.tier);
			const held = row[key];
			if (held && (held.tiered === tiered ? held.percent >= percent : !held.tiered)) continue;
			row[key] = { percent, resetsAt: limit.window?.resetsAt, tiered };
		}
		if (row.fiveHour || row.sevenDay) byProvider.set(provider, row);
	}
	return [...byProvider.values()];
}

function refresh(): void {
	const session = liveSession;
	if (inflight || typeof session?.fetchUsageReports !== "function") return;
	if (fetchedAt > 0 && Date.now() - fetchedAt < REFRESH_MS) return;
	inflight = true;
	// Detached on purpose: the status line renders synchronously. A throw here
	// would be an uncaught rejection (fatal to the session), hence the catch.
	session
		.fetchUsageReports(AbortSignal.timeout(8_000))
		.then((reports) => {
			rows = parse(reports);
			repaint?.();
		})
		.catch(() => {})
		.finally(() => {
			fetchedAt = Date.now();
			inflight = false;
		});
}

/** Core's `IN5`. */
function quotaColor(percent: number): string {
	if (percent >= 80) return "error";
	if (percent >= 50) return "warning";
	return "muted";
}

/** 5h windows land today: a wall clock is more useful than a countdown. */
function resetClock(resetsAt: number | undefined, hour12: boolean): string {
	if (resetsAt === undefined || !Number.isFinite(resetsAt)) return "";
	return new Intl.DateTimeFormat(undefined, {
		hour: "numeric",
		minute: "2-digit",
		hour12,
	}).format(new Date(resetsAt));
}

/** Same day -> the clock is enough; otherwise name the day it lands on. */
function resetDay(resetsAt: number | undefined, hour12: boolean, now: number): string {
	if (resetsAt === undefined || !Number.isFinite(resetsAt)) return "";
	const at = new Date(resetsAt);
	const clock = resetClock(resetsAt, hour12);
	if (at.toDateString() === new Date(now).toDateString()) return clock;
	const day = new Intl.DateTimeFormat(undefined, { weekday: "short" }).format(at);
	return `${day} ${clock}`;
}

SEGMENTS.quota = {
	id: "quota",
	render(ctx) {
		liveSession = ctx.session;
		refresh();
		if (rows.length === 0) return { content: "", visible: false };

		const opts = (ctx.options.quota ?? {}) as { allProviders?: boolean };
		const current = ctx.session.state?.model?.provider ?? ctx.session.model?.provider;
		const hour12 = (ctx.options.time?.format ?? "24h") === "12h";
		// Default to the provider actually serving this session; the others are
		// noise until you switch models, and `/model` re-renders this segment.
		const visible = opts.allProviders
			? [...rows].sort((a, b) =>
					a.provider === current ? -1 : b.provider === current ? 1 : a.label.localeCompare(b.label),
				)
			: rows.filter((row) => row.provider === current);
		if (visible.length === 0) return { content: "", visible: false };

		const now = Date.now();
		const chunks = visible.map((row) => {
			const windows: string[] = [];
			const window = (name: string, win: Window | undefined, at: string) => {
				if (!win) return;
				const pct = theme.fg(quotaColor(win.percent), `${Math.round(win.percent)}%`);
				windows.push(`${name} ${pct}${at ? theme.fg("dim", ` (${at})`) : ""}`);
			};
			window("5h", row.fiveHour, resetClock(row.fiveHour?.resetsAt, hour12));
			window("7d", row.sevenDay, resetDay(row.sevenDay?.resetsAt, hour12, now));
			const label = opts.allProviders ? `${theme.fg("dim", row.label)} ` : "";
			return `${label}${windows.join(theme.sep.dot)}`;
		});

		const body = chunks.join("  ");
		return { content: theme.icon.time ? `${theme.icon.time} ${body}` : body, visible: true };
	},
};
