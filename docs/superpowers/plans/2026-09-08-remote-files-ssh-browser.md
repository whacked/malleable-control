# Remote Files SSH Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A BB sidebar panel that browses a remote host's filesystem over plain SSH, in ranger-style Miller columns with image and text previews and a local blob cache.

**Architecture:** Every remote operation is one short-lived `ssh` process, made cheap by a ControlMaster socket so only the first call pays a handshake. Structured data comes from a Python helper streamed on ssh's **stdin**, so it exists only in that process's memory and never touches remote disk; hosts without `python3` fall back to a `find` + `stat` shell tier. Bytes are cached locally under `.cache/`, keyed by content identity, and served to the browser as real bytes over `bb.http.route` rather than base64 through RPC.

**Tech Stack:** TypeScript, `@get-bb/plugin-sdk` 0.4.47, Zod 4, React 19, `better-sqlite3` 12 (externalized by the bundler, resolved at runtime), `node --test` on Node 24 (native TS type stripping), Python 3 on the remote (tier A only).

**Spec:** `docs/superpowers/specs/2026-09-08-remote-files-ssh-browser-design.md`

**Working directory:** `bb-plugins/bb-plugin-remote-files` — its own git repository. All `git` commands in this plan run inside it. Never commit this plugin from the parent `malleable-control` repo.

## Global Constraints

- **Nothing is written to remote disk.** Not a helper script, not a temp file, not a cache. Any step that would create a remote file is wrong.
- **Read-only.** No rename, delete, mkdir, upload, or download in this plan.
- **No machine-specific values in the repo.** Host and root directory resolve at runtime; both blank by default.
- **Local commands are argv arrays, never shell strings.** `spawn("ssh", argv)` with no `shell: true`, ever.
- **Remote arguments are always shell-quoted** with `shellQuote` from Task 2. ssh runs its command through a remote login shell, so an unquoted path containing a space is a bug and a path containing `;` is a vulnerability.
- **`-o BatchMode=yes` on every ssh call.** Key/agent auth only; a password prompt must fail fast rather than hang.
- **The ControlMaster socket lives in `os.tmpdir()`, not the plugin directory.** Unix socket paths cap at 104 bytes on macOS and this checkout's path is already ~85.
- **The cache lives in `.cache/` inside the plugin directory** and is gitignored. Never commit a cache file.
- Test imports use explicit `.ts` extensions (`from "../lib/target.ts"`), matching `bb-plugin-nats-bus`.
- Every task ends green: `npm test` and `npm run typecheck` both pass before the commit.

---

### Task 1: Target parsing and configuration resolution

Turns the user's `user@host:port` string into validated pieces, and resolves the four-tier configuration. Both are pure functions with no I/O, which is why they come first.

**Files:**
- Create: `lib/target.ts`
- Create: `test/target.test.ts`
- Modify: `tsconfig.json` (add `"test"` to `include`)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `type SshTarget = { user: string | null; host: string; port: number | null }`
  - `parseTarget(raw: string): { ok: true; target: SshTarget } | { ok: false; error: string }`
  - `destinationOf(target: SshTarget): string`
  - `type ConfigSource = "override" | "setting" | "env" | "unset"`
  - `type ResolvedConfig = { sshTarget: string; rootDir: string; source: ConfigSource }`
  - `resolveConfig(tiers: { override?: Partial<Pick<ResolvedConfig, "sshTarget" | "rootDir">> | null; setting?: { sshTarget?: string; rootDir?: string } | null; env?: { sshTarget?: string; rootDir?: string } | null }): ResolvedConfig`

- [ ] **Step 1: Add `test` to the TypeScript include list**

In `tsconfig.json`, change the `include` array to:

```json
  "include": ["server.ts", "app.tsx", "components", "lib", "hooks", "test"]
```

- [ ] **Step 2: Write the failing tests**

Create `test/target.test.ts`:

```ts
import { deepStrictEqual, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";
import { destinationOf, parseTarget, resolveConfig } from "../lib/target.ts";

describe("parseTarget", () => {
  it("accepts every documented form", () => {
    deepStrictEqual(parseTarget("alice@box.example.com:2222"), {
      ok: true,
      target: { user: "alice", host: "box.example.com", port: 2222 },
    });
    deepStrictEqual(parseTarget("box.example.com:2222"), {
      ok: true,
      target: { user: null, host: "box.example.com", port: 2222 },
    });
    deepStrictEqual(parseTarget("alice@box"), {
      ok: true,
      target: { user: "alice", host: "box", port: null },
    });
    deepStrictEqual(parseTarget("eda-test"), {
      ok: true,
      target: { user: null, host: "eda-test", port: null },
    });
  });

  it("trims surrounding whitespace", () => {
    deepStrictEqual(parseTarget("  box  "), {
      ok: true,
      target: { user: null, host: "box", port: null },
    });
  });

  // A host that reached argv could otherwise smuggle an ssh option or a
  // shell metacharacter. Each of these must be refused, not escaped.
  it("refuses shell- and flag-shaped input", () => {
    for (const bad of [
      "-oProxyCommand=touch /tmp/pwned",
      "box; rm -rf /",
      "box$(whoami)",
      "box`id`",
      "box|tee",
      "box host",
      "box\nhost",
      "",
      "   ",
      "@box",
      "alice@",
    ]) {
      strictEqual(parseTarget(bad).ok, false, `expected refusal: ${bad}`);
    }
  });

  it("refuses out-of-range and non-numeric ports", () => {
    strictEqual(parseTarget("box:0").ok, false);
    strictEqual(parseTarget("box:65536").ok, false);
    strictEqual(parseTarget("box:22x").ok, false);
  });

  it("reports why it refused", () => {
    const result = parseTarget("");
    strictEqual(result.ok, false);
    if (!result.ok) strictEqual(result.error, "An SSH target is required");
  });
});

describe("destinationOf", () => {
  it("rejoins the user but never the port", () => {
    strictEqual(
      destinationOf({ user: "alice", host: "box", port: 2222 }),
      "alice@box",
    );
    strictEqual(destinationOf({ user: null, host: "box", port: null }), "box");
  });
});

describe("resolveConfig", () => {
  it("prefers the session override over everything", () => {
    const resolved = resolveConfig({
      override: { sshTarget: "o", rootDir: "/o" },
      setting: { sshTarget: "s", rootDir: "/s" },
      env: { sshTarget: "e", rootDir: "/e" },
    });
    deepStrictEqual(resolved, {
      sshTarget: "o",
      rootDir: "/o",
      source: "override",
    });
  });

  it("falls through setting, then env, then unset", () => {
    strictEqual(
      resolveConfig({ setting: { sshTarget: "s", rootDir: "/s" }, env: { sshTarget: "e" } }).source,
      "setting",
    );
    strictEqual(resolveConfig({ env: { sshTarget: "e", rootDir: "/e" } }).source, "env");
    deepStrictEqual(resolveConfig({}), {
      sshTarget: "",
      rootDir: "",
      source: "unset",
    });
  });

  // A tier that exists but holds only blanks must not win: a saved setting
  // someone cleared should let the env var through, not shadow it.
  it("treats a blank value as absent", () => {
    strictEqual(
      resolveConfig({
        setting: { sshTarget: "   ", rootDir: "" },
        env: { sshTarget: "e", rootDir: "/e" },
      }).source,
      "env",
    );
  });

  // The target decides the source; a root dir alone is not a configuration.
  it("takes the root dir from the tier that supplied the target", () => {
    const resolved = resolveConfig({
      setting: { sshTarget: "s" },
      env: { sshTarget: "e", rootDir: "/e" },
    });
    deepStrictEqual(resolved, { sshTarget: "s", rootDir: "", source: "setting" });
  });
});
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — `Cannot find module '../lib/target.ts'`

- [ ] **Step 4: Implement `lib/target.ts`**

```ts
// Parsing and configuration resolution for the remote target. Pure: no I/O,
// no ssh, no settings access — the callers supply the tiers.

/** A parsed SSH destination. `port` is null when ssh_config should decide. */
export type SshTarget = { user: string | null; host: string; port: number | null };

/**
 * Host and user character classes. Deliberately narrower than what ssh would
 * accept: everything here ends up in an argv, so a value that could be read
 * as an option (`-o...`) or as shell syntax is refused rather than escaped.
 * Requiring an alphanumeric first character is what rules out the option
 * forms. IPv6 literals are not supported; use an ssh_config alias.
 */
const HOST_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const USER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

export function parseTarget(
  raw: string,
): { ok: true; target: SshTarget } | { ok: false; error: string } {
  const trimmed = raw.trim();
  if (trimmed === "") return { ok: false, error: "An SSH target is required" };

  let rest = trimmed;
  let user: string | null = null;
  const at = rest.indexOf("@");
  if (at !== -1) {
    user = rest.slice(0, at);
    rest = rest.slice(at + 1);
    if (!USER_PATTERN.test(user)) {
      return { ok: false, error: `Not a usable SSH user: "${user}"` };
    }
  }

  let port: number | null = null;
  const colon = rest.lastIndexOf(":");
  if (colon !== -1) {
    const portText = rest.slice(colon + 1);
    if (!/^\d+$/.test(portText)) {
      return { ok: false, error: `Not a port number: "${portText}"` };
    }
    port = Number(portText);
    if (port < 1 || port > 65535) {
      return { ok: false, error: `Port out of range: ${port}` };
    }
    rest = rest.slice(0, colon);
  }

  if (!HOST_PATTERN.test(rest)) {
    return {
      ok: false,
      error:
        `Not a usable SSH host: "${rest}". Use a host name, an address, or ` +
        `an ~/.ssh/config alias — letters, digits, and . _ - only.`,
    };
  }
  return { ok: true, target: { user, host: rest, port } };
}

/** The `[user@]host` argument ssh takes. The port travels separately, as -p. */
export function destinationOf(target: SshTarget): string {
  return target.user === null ? target.host : `${target.user}@${target.host}`;
}

export type ConfigSource = "override" | "setting" | "env" | "unset";
export type ResolvedConfig = {
  sshTarget: string;
  rootDir: string;
  source: ConfigSource;
};
type Tier = { sshTarget?: string; rootDir?: string } | null | undefined;

function clean(value: string | undefined): string {
  return (value ?? "").trim();
}

/**
 * Resolve the effective configuration, most specific tier first. A tier wins
 * by supplying a target; its root dir comes along even when blank, so a tier
 * is adopted whole rather than assembled from pieces of several.
 */
export function resolveConfig(tiers: {
  override?: Tier;
  setting?: Tier;
  env?: Tier;
}): ResolvedConfig {
  const ordered: Array<[ConfigSource, Tier]> = [
    ["override", tiers.override],
    ["setting", tiers.setting],
    ["env", tiers.env],
  ];
  for (const [source, tier] of ordered) {
    const sshTarget = clean(tier?.sshTarget);
    if (sshTarget !== "") {
      return { sshTarget, rootDir: clean(tier?.rootDir), source };
    }
  }
  return { sshTarget: "", rootDir: "", source: "unset" };
}
```

- [ ] **Step 5: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS

- [ ] **Step 6: Commit**

```bash
git add tsconfig.json lib/target.ts test/target.test.ts
git commit -m "Parse the SSH target, and resolve config by tier

The host and user patterns refuse anything option- or shell-shaped
rather than escaping it: these values reach an argv, and an argv is
not a place to be clever.

A tier wins by supplying a target and is then adopted whole, so a
half-filled setting cannot borrow the env var's root directory."
```

---

### Task 2: SSH argv construction, shell quoting, and the control socket path

Still pure. This is where the multiplexing options and the remote-quoting rule get pinned down and tested, before any process is spawned.

**Files:**
- Create: `lib/ssh-argv.ts`
- Create: `test/ssh-argv.test.ts`

**Interfaces:**
- Consumes: `SshTarget`, `destinationOf` from `lib/target.ts`.
- Produces:
  - `shellQuote(value: string): string`
  - `controlSocketPath(target: SshTarget, tmpDir?: string): string`
  - `buildSshArgv(opts: { target: SshTarget; controlPath: string; remote: string[]; connectTimeoutSec?: number; persistSec?: number }): string[]`

- [ ] **Step 1: Write the failing tests**

Create `test/ssh-argv.test.ts`:

```ts
import { execFileSync } from "node:child_process";
import { deepStrictEqual, ok, strictEqual, throws } from "node:assert/strict";
import { describe, it } from "node:test";
import { buildSshArgv, controlSocketPath, shellQuote } from "../lib/ssh-argv.ts";

describe("shellQuote", () => {
  // The authority on what a shell does with a string is a shell. Rather than
  // assert on the quoted text, run it and check what the shell received.
  it("round-trips every hostile string through a real shell", () => {
    for (const value of [
      "plain",
      "with space",
      "it's",
      "a'b'c",
      "semi; rm -rf /",
      "$(whoami)",
      "`id`",
      "back\\slash",
      "new\nline",
      "tab\there",
      "*glob?",
      "~/tilde",
      "unicode-é中",
      "",
    ]) {
      const out = execFileSync("/bin/sh", ["-c", `printf %s ${shellQuote(value)}`], {
        encoding: "utf8",
      });
      strictEqual(out, value, `mangled: ${JSON.stringify(value)}`);
    }
  });
});

describe("controlSocketPath", () => {
  it("stays inside the 104-byte sun_path limit", () => {
    const path = controlSocketPath({ user: "alice", host: "box", port: 2222 });
    ok(Buffer.byteLength(path) < 104, `too long (${path.length}): ${path}`);
  });

  it("throws rather than returning a path ssh cannot bind", () => {
    throws(
      () => controlSocketPath({ user: null, host: "box", port: null }, `/${"x".repeat(120)}`),
      /104-byte limit/,
    );
  });

  it("is stable per target and distinct across targets", () => {
    const a = controlSocketPath({ user: "alice", host: "box", port: null });
    const b = controlSocketPath({ user: "alice", host: "box", port: null });
    const c = controlSocketPath({ user: "bob", host: "box", port: null });
    const d = controlSocketPath({ user: "alice", host: "box", port: 2222 });
    strictEqual(a, b);
    ok(a !== c, "user must affect the socket");
    ok(a !== d, "port must affect the socket");
  });
});

describe("buildSshArgv", () => {
  it("builds the multiplexed argv exactly", () => {
    deepStrictEqual(
      buildSshArgv({
        target: { user: "alice", host: "box", port: 2222 },
        controlPath: "/tmp/bb-rf-abcd1234",
        remote: ["ls", "-a"],
      }),
      [
        "-T",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "ControlMaster=auto",
        "-o", "ControlPath=/tmp/bb-rf-abcd1234",
        "-o", "ControlPersist=300",
        "-p", "2222",
        "alice@box",
        "'ls' '-a'",
      ],
    );
  });

  it("omits -p when no port was given", () => {
    const argv = buildSshArgv({
      target: { user: null, host: "box", port: null },
      controlPath: "/tmp/s",
      remote: ["true"],
    });
    strictEqual(argv.includes("-p"), false);
    strictEqual(argv.at(-2), "box");
  });

  // ssh hands its command to a remote login shell, so the remote words must
  // arrive as one already-quoted string. A path with a space that arrives as
  // two words is a bug; a path with a semicolon that does is an exploit.
  it("quotes the remote words into a single argument", () => {
    const argv = buildSshArgv({
      target: { user: null, host: "box", port: null },
      controlPath: "/tmp/s",
      remote: ["cat", "/data/my files/a;b.txt"],
    });
    strictEqual(argv.at(-1), `'cat' '/data/my files/a;b.txt'`);
    strictEqual(argv.filter((a) => a.includes("a;b.txt")).length, 1);
  });

  // Every remote word is quoted unconditionally. A denylist of "dangerous"
  // characters is not good enough: ~ tilde-expands and # opens a comment,
  // and neither looks dangerous until the remote shell reads it.
  it("quotes words a character denylist would let through", () => {
    for (const word of ["~private", "~root/x", "#notacomment", "plain"]) {
      const argv = buildSshArgv({
        target: { user: null, host: "box", port: null },
        controlPath: "/tmp/s",
        remote: ["cat", word],
      });
      strictEqual(argv.at(-1), `'cat' '${word}'`, word);
    }
  });

  it("honours overridden timeouts", () => {
    const argv = buildSshArgv({
      target: { user: null, host: "box", port: null },
      controlPath: "/tmp/s",
      remote: ["true"],
      connectTimeoutSec: 3,
      persistSec: 60,
    });
    ok(argv.includes("ConnectTimeout=3"));
    ok(argv.includes("ControlPersist=60"));
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — `Cannot find module '../lib/ssh-argv.ts'`

- [ ] **Step 3: Implement `lib/ssh-argv.ts`**

```ts
// Building the ssh argv. Pure and side-effect free, so the security-relevant
// decisions — quoting, and what may reach an option slot — are unit testable
// without a network or a remote host.
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { destinationOf, type SshTarget } from "./target.ts";

/**
 * Quote one word for a POSIX shell. ssh always runs its command through a
 * login shell on the far side, so this is not optional decoration: it is what
 * stands between a filename and the remote shell's syntax.
 *
 * Single quotes suspend every metacharacter, so only the single quote itself
 * needs handling: close, emit an escaped quote, reopen.
 */
export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

/**
 * Where the ControlMaster socket lives.
 *
 * Not in the plugin directory: sun_path is 104 bytes on macOS and this
 * checkout's path is already ~85, so a socket there would fail at bind with a
 * baffling error. The socket is ephemeral connection state rather than cached
 * data, so tmpdir is also the honest place for it.
 */
export function controlSocketPath(target: SshTarget, tmpDir = tmpdir()): string {
  const identity = `${target.user ?? ""}@${target.host}:${target.port ?? ""}`;
  const digest = createHash("sha256").update(identity).digest("hex").slice(0, 12);
  const path = join(tmpDir, `bb-rf-${digest}`);
  // Checked here rather than left to ssh, which fails at bind with an error
  // that names neither the limit nor TMPDIR.
  if (Buffer.byteLength(path) >= 104) {
    throw new Error(
      `The control socket path is ${Buffer.byteLength(path)} bytes, over the ` +
        `104-byte limit for a Unix socket. Point TMPDIR at a shorter path.`,
    );
  }
  return path;
}

export function buildSshArgv(opts: {
  target: SshTarget;
  controlPath: string;
  remote: string[];
  connectTimeoutSec?: number;
  persistSec?: number;
}): string[] {
  const { target, controlPath, remote } = opts;
  return [
    // No tty: ssh then leaves stdout alone, so file bytes cross the wire raw.
    "-T",
    // Key or agent auth only. A host that would prompt fails immediately
    // instead of hanging on a prompt nobody can see or answer.
    "-o", "BatchMode=yes",
    "-o", `ConnectTimeout=${opts.connectTimeoutSec ?? 10}`,
    // The multiplexing that makes a process-per-operation design affordable:
    // the first call handshakes, the rest ride the existing connection.
    "-o", "ControlMaster=auto",
    "-o", `ControlPath=${controlPath}`,
    "-o", `ControlPersist=${opts.persistSec ?? 300}`,
    ...(target.port === null ? [] : ["-p", String(target.port)]),
    destinationOf(target),
    remote.map(shellQuote).join(" "),
  ];
}
```

- [ ] **Step 4: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ssh-argv.ts test/ssh-argv.test.ts
git commit -m "Build the multiplexed ssh argv, and quote the remote words

ssh hands its command to a login shell on the far side, so the remote
words are quoted into a single argument. The quoting test asserts
against a real /bin/sh rather than against expected text, because the
shell is the only authority on what the shell does.

The control socket goes in tmpdir: sun_path is 104 bytes and this
checkout's path is already 85 of them."
```

---

### Task 3: Running ssh

The first task that spawns a process. Tested against an injected fake `ssh` so the behaviour under timeout, oversized output, and non-zero exit is exercised without a remote host.

**Files:**
- Create: `lib/ssh-run.ts`
- Create: `test/ssh-run.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks (it takes a prebuilt argv).
- Produces:
  - `type SshResult = { code: number | null; stdout: Buffer; stderr: string; timedOut: boolean; truncated: boolean }`
  - `runSsh(opts: { argv: string[]; stdin?: string | Buffer; timeoutMs?: number; maxBytes?: number; sshBin?: string }): Promise<SshResult>`
  - `classifySshFailure(result: SshResult): string | null`

- [ ] **Step 1: Write the failing tests**

Create `test/ssh-run.test.ts`:

```ts
import { mkdtempSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ok, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";
import { classifySshFailure, runSsh } from "../lib/ssh-run.ts";

/** A stand-in for the ssh binary, so the transport is testable offline. */
const dir = mkdtempSync(join(tmpdir(), "rf-fake-ssh-"));
function fake(name: string, body: string): string {
  const path = join(dir, name);
  writeFileSync(path, `#!/bin/sh\n${body}\n`);
  chmodSync(path, 0o755);
  return path;
}

const echoArgs = fake("echo-args", `for a in "$@"; do printf '%s\\n' "$a"; done`);
const echoStdin = fake("echo-stdin", `cat`);
const fails = fake("fails", `echo "boom" >&2; exit 42`);
// The trailing command stops sh from exec-replacing itself, so this fixture
// reliably has a grandchild — which is the case that breaks a naive kill.
const sleeps = fake("sleeps", `sleep 30\necho done`);
const floods = fake("floods", `head -c 1000000 /dev/zero`);
const binary = fake("binary", `printf '\\000\\001\\377\\376'`);

describe("runSsh", () => {
  it("passes argv through untouched", async () => {
    const result = await runSsh({ argv: ["-T", "a b", "c;d"], sshBin: echoArgs });
    strictEqual(result.code, 0);
    strictEqual(result.stdout.toString("utf8"), "-T\na b\nc;d\n");
  });

  it("writes stdin and returns raw bytes unmangled", async () => {
    const result = await runSsh({ argv: [], stdin: "hello", sshBin: echoStdin });
    strictEqual(result.stdout.toString("utf8"), "hello");
    const bin = await runSsh({ argv: [], sshBin: binary });
    strictEqual(bin.stdout.toString("hex"), "0001fffe");
  });

  it("surfaces exit code and stderr", async () => {
    const result = await runSsh({ argv: [], sshBin: fails });
    strictEqual(result.code, 42);
    strictEqual(result.stderr.trim(), "boom");
  });

  it("kills a hung call within the timeout, not when the hang ends", async () => {
    const started = Date.now();
    const result = await runSsh({ argv: [], timeoutMs: 250, sshBin: sleeps });
    const elapsed = Date.now() - started;
    strictEqual(result.timedOut, true);
    // The elapsed assertion is the point. The flag alone passes even when the
    // promise settles 30s late: killing only the immediate pid leaves the
    // grandchild holding the stdio pipe, and `close` waits for it.
    ok(elapsed < 5_000, `settled after ${elapsed}ms — the kill missed the grandchild`);
  });

  it("does not crash the host when the child exits before stdin is written", async () => {
    const result = await runSsh({ argv: [], stdin: "x".repeat(100_000), sshBin: fails });
    strictEqual(result.code, 42);
  });

  it("stops reading past maxBytes rather than buffering forever", async () => {
    const result = await runSsh({ argv: [], maxBytes: 1024, sshBin: floods });
    strictEqual(result.truncated, true);
    ok(result.stdout.length <= 1024 + 65536, `kept ${result.stdout.length} bytes`);
  });

  it("reports a missing ssh binary instead of throwing", async () => {
    const result = await runSsh({ argv: [], sshBin: join(dir, "nope") });
    ok(result.code !== 0);
    ok(/nope|ENOENT/.test(result.stderr), result.stderr);
  });
});

describe("classifySshFailure", () => {
  const base = { code: 255, stdout: Buffer.alloc(0), timedOut: false, truncated: false };

  it("tells auth failure apart from unreachability", () => {
    ok(/key or agent/i.test(
      classifySshFailure({ ...base, stderr: "Permission denied (publickey)." }) ?? "",
    ));
    ok(/reach/i.test(
      classifySshFailure({ ...base, stderr: "ssh: connect to host box port 22: Connection refused" }) ?? "",
    ));
    ok(/host key/i.test(
      classifySshFailure({ ...base, stderr: "Host key verification failed." }) ?? "",
    ));
  });

  it("says when it stopped reading an oversized reply", () => {
    const message = classifySshFailure({ ...base, code: null, truncated: true, stderr: "" });
    ok(/too large/i.test(message ?? ""), message ?? "(null)");
  });

  it("says nothing about a successful call", () => {
    strictEqual(
      classifySshFailure({ ...base, code: 0, stderr: "" }),
      null,
    );
  });

  it("falls back to the raw stderr it did not recognise", () => {
    const message = classifySshFailure({ ...base, stderr: "something novel" });
    ok((message ?? "").includes("something novel"));
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — `Cannot find module '../lib/ssh-run.ts'`

- [ ] **Step 3: Implement `lib/ssh-run.ts`**

```ts
// Running one ssh process and collecting its output. Kept separate from argv
// construction so the argv rules stay testable without spawning anything, and
// so this file can be exercised against a fake ssh binary.
import { spawn } from "node:child_process";

export type SshResult = {
  code: number | null;
  stdout: Buffer;
  stderr: string;
  timedOut: boolean;
  /** Output hit maxBytes; stdout holds a prefix and the call was killed. */
  truncated: boolean;
};

/** Ceiling on one call's stdout. A listing or preview never approaches this. */
const DEFAULT_MAX_BYTES = 64 * 1024 * 1024;
const DEFAULT_TIMEOUT_MS = 30_000;

export function runSsh(opts: {
  argv: string[];
  stdin?: string | Buffer;
  timeoutMs?: number;
  maxBytes?: number;
  sshBin?: string;
}): Promise<SshResult> {
  const maxBytes = opts.maxBytes ?? DEFAULT_MAX_BYTES;
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  return new Promise<SshResult>((resolve) => {
    const child = spawn(opts.sshBin ?? "ssh", opts.argv, {
      stdio: ["pipe", "pipe", "pipe"],
      // Its own process group. ssh is routinely reached through a wrapper
      // script or a ProxyCommand, and killing only the immediate pid leaves
      // the grandchild alive holding the stdio pipe — so `close` never fires
      // and the timeout we are enforcing waits out the hang it exists to cut.
      detached: true,
    });

    /** Kill the whole group. An already-dead child is not an error. */
    const killTree = () => {
      try {
        if (child.pid !== undefined) process.kill(-child.pid, "SIGKILL");
        else child.kill("SIGKILL");
      } catch {
        child.kill("SIGKILL");
      }
    };

    const chunks: Buffer[] = [];
    let total = 0;
    let stderr = "";
    let timedOut = false;
    let truncated = false;
    let settled = false;

    const timer = setTimeout(() => {
      timedOut = true;
      killTree();
    }, timeoutMs);

    const finish = (code: number | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({
        code,
        stdout: Buffer.concat(chunks),
        stderr,
        timedOut,
        truncated,
      });
    };

    child.stdout.on("data", (chunk: Buffer) => {
      total += chunk.length;
      if (total > maxBytes) {
        truncated = true;
        killTree();
        return;
      }
      chunks.push(chunk);
    });
    child.stderr.on("data", (chunk: Buffer) => {
      // Bounded: a pathological stderr must not become a memory problem.
      if (stderr.length < 64 * 1024) stderr += chunk.toString("utf8");
    });

    // A spawn failure (no such binary, not executable) is a result, not an
    // exception: every caller already handles a non-zero code.
    child.on("error", (cause: Error) => {
      stderr = stderr === "" ? cause.message : `${stderr}\n${cause.message}`;
      finish(-1);
    });
    child.on("close", (code) => finish(code));

    // A child that exits before stdin is fully written raises EPIPE. With no
    // listener Node rethrows it as an unhandled error event and takes the whole
    // plugin host down; the exit code already tells the caller what happened.
    child.stdin.on("error", () => {});
    if (opts.stdin !== undefined) child.stdin.end(opts.stdin);
    else child.stdin.end();
  });
}

/**
 * Turn a failed call into something a panel can display. ssh reports almost
 * everything as exit 255, so the distinctions that matter to a user — wrong
 * key, wrong host, unknown host key — live in stderr and only here.
 */
export function classifySshFailure(result: SshResult): string | null {
  if (result.code === 0 && !result.timedOut && !result.truncated) return null;
  if (result.timedOut) return "The host did not answer in time.";
  if (result.truncated) {
    return "The reply was too large to read, and was stopped part-way.";
  }
  const stderr = result.stderr.trim();
  if (/permission denied|no supported authentication/i.test(stderr)) {
    return (
      "The host refused the key. This plugin runs ssh with BatchMode, so it " +
      "authenticates by key or agent only and never by password."
    );
  }
  if (/host key verification failed|remote host identification has changed/i.test(stderr)) {
    return `Host key verification failed. Resolve it with ssh directly, then retry.\n${stderr}`;
  }
  if (/could not resolve|name or service not known|nodename nor servname/i.test(stderr)) {
    return `Could not resolve the host name.\n${stderr}`;
  }
  if (/connection refused|no route to host|connection timed out|operation timed out/i.test(stderr)) {
    return `Could not reach the host.\n${stderr}`;
  }
  return stderr === "" ? `ssh exited with code ${result.code}` : stderr;
}
```

- [ ] **Step 4: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ssh-run.ts test/ssh-run.test.ts
git commit -m "Run ssh, with timeouts, byte caps, and legible failures

A fake ssh binary is injected rather than placed on PATH, which makes
the timeout, oversized-output, and missing-binary paths testable
offline and deterministic.

ssh reports nearly everything as exit 255, so the distinctions a user
can act on — wrong key, unknown host key, unreachable — are recovered
from stderr in one place."
```

---

### Task 4: The capability probe

One round trip at Connect time decides which tier the session runs in and whether remote resizing is possible.

**Files:**
- Create: `lib/probe.ts`
- Create: `test/probe.test.ts`

**Interfaces:**
- Consumes: nothing (the parser is pure; the caller runs the script).
- Produces:
  - `PROBE_SCRIPT: string` — the remote sh source, to pass as `remote: ["sh", "-c", PROBE_SCRIPT]`
  - `type StatFlavor = "gnu" | "bsd" | "none"`
  - `type Capabilities = { tier: "python" | "shell"; python3: boolean; pil: boolean; magick: string | null; vips: boolean; statFlavor: StatFlavor; uname: string; resize: "pil" | "magick" | "vips" | "none" }`
  - `parseProbe(stdout: string): Capabilities`
  - `describeCapabilities(caps: Capabilities): string`

- [ ] **Step 1: Write the failing tests**

Create `test/probe.test.ts`:

```ts
import { execFileSync } from "node:child_process";
import { ok, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";
import { PROBE_SCRIPT, describeCapabilities, parseProbe } from "../lib/probe.ts";

describe("PROBE_SCRIPT", () => {
  // The script runs on someone else's machine under /bin/sh. Running it here
  // proves it is valid POSIX sh and that its output parses.
  it("runs under /bin/sh and produces parseable output", () => {
    const stdout = execFileSync("/bin/sh", ["-c", PROBE_SCRIPT], { encoding: "utf8" });
    const caps = parseProbe(stdout);
    ok(caps.uname.length > 0, "uname should be reported");
    ok(["gnu", "bsd", "none"].includes(caps.statFlavor));
  });

  // The whole point of the design is that the far side is left untouched,
  // and this assertion is that constraint's only automated enforcement — so
  // it is written to fail closed. Matching `> /absolute/path` would miss
  // `> relative`, and would miss every write that is not a redirection.
  it("writes nowhere but stdout", () => {
    const stripped = PROBE_SCRIPT
      .replaceAll(">/dev/null", "")
      .replaceAll("> /dev/null", "")
      .replaceAll("2>&1", "");
    strictEqual(
      stripped.includes(">"),
      false,
      `probe redirects somewhere other than /dev/null:\n${stripped}`,
    );
    for (const writer of [
      "mktemp", "tee", "dd ", "touch", "mkdir", "truncate",
      "sed -i", "cp ", "mv ", "install ", "open(",
    ]) {
      strictEqual(PROBE_SCRIPT.includes(writer), false, `probe uses ${writer}`);
    }
  });
});

describe("parseProbe", () => {
  const gnuBox = [
    "bin.python3=/usr/bin/python3",
    "bin.magick=",
    "bin.convert=/usr/bin/convert",
    "bin.vips=",
    "pil=1",
    "stat=gnu",
    "uname=Linux",
  ].join("\n");

  it("reads a full-featured host", () => {
    const caps = parseProbe(gnuBox);
    strictEqual(caps.tier, "python");
    strictEqual(caps.python3, true);
    strictEqual(caps.pil, true);
    strictEqual(caps.magick, "convert");
    strictEqual(caps.statFlavor, "gnu");
    strictEqual(caps.resize, "pil");
  });

  it("prefers magick over convert when both exist", () => {
    const caps = parseProbe(gnuBox.replace("bin.magick=", "bin.magick=/usr/bin/magick"));
    strictEqual(caps.magick, "magick");
  });

  it("drops to the shell tier without python3", () => {
    const caps = parseProbe(gnuBox.replace("bin.python3=/usr/bin/python3", "bin.python3="));
    strictEqual(caps.tier, "shell");
    strictEqual(caps.python3, false);
    // PIL is unreachable without python3, so the probe falls to convert.
    strictEqual(caps.resize, "magick");
  });

  it("reports no resize path when the host has no image tooling", () => {
    const bare = ["bin.python3=", "bin.magick=", "bin.convert=", "bin.vips=", "pil=0", "stat=bsd", "uname=Darwin"].join("\n");
    const caps = parseProbe(bare);
    strictEqual(caps.resize, "none");
    strictEqual(caps.statFlavor, "bsd");
  });

  it("survives unknown and malformed lines", () => {
    const caps = parseProbe(`${gnuBox}\nnonsense\nfuture.key=value\n\n`);
    strictEqual(caps.tier, "python");
  });
});

describe("describeCapabilities", () => {
  it("names the tier and the resize path in one line", () => {
    const text = describeCapabilities(parseProbe("bin.python3=/usr/bin/python3\npil=1\nstat=gnu\nuname=Linux"));
    ok(/python/i.test(text));
    ok(/Pillow|PIL/i.test(text));
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — `Cannot find module '../lib/probe.ts'`

- [ ] **Step 3: Implement `lib/probe.ts`**

```ts
// What the far side can do. Run once per connection; the answer pins the tier
// for the session and decides whether large images can be resized before they
// cross the wire.

/**
 * POSIX sh, deliberately dull. It creates nothing, writes nowhere but stdout,
 * and emits `key=value` lines — easier to get right than remote JSON quoting,
 * and forgiving of a host that adds a line we do not know about yet.
 */
export const PROBE_SCRIPT = [
  `for t in python3 magick convert vips; do`,
  `  p=\`command -v $t 2>/dev/null\` || p=''`,
  `  echo "bin.$t=$p"`,
  `done`,
  `if stat -c %s /dev/null >/dev/null 2>&1; then echo "stat=gnu"`,
  `elif stat -f %z /dev/null >/dev/null 2>&1; then echo "stat=bsd"`,
  `else echo "stat=none"; fi`,
  `if python3 -c 'import PIL' >/dev/null 2>&1; then echo "pil=1"; else echo "pil=0"; fi`,
  `echo "uname=\`uname -s\`"`,
].join("\n");

export type StatFlavor = "gnu" | "bsd" | "none";
export type Capabilities = {
  tier: "python" | "shell";
  python3: boolean;
  pil: boolean;
  /** The ImageMagick entry point to call, "magick" or "convert", else null. */
  magick: string | null;
  vips: boolean;
  statFlavor: StatFlavor;
  uname: string;
  resize: "pil" | "magick" | "vips" | "none";
};

export function parseProbe(stdout: string): Capabilities {
  const fields = new Map<string, string>();
  for (const line of stdout.split("\n")) {
    const eq = line.indexOf("=");
    if (eq > 0) fields.set(line.slice(0, eq).trim(), line.slice(eq + 1).trim());
  }
  const has = (key: string) => (fields.get(key) ?? "") !== "";

  const python3 = has("bin.python3");
  // PIL is only reachable through python3, so a stale pil=1 cannot outvote a
  // missing interpreter.
  const pil = python3 && fields.get("pil") === "1";
  const magick = has("bin.magick") ? "magick" : has("bin.convert") ? "convert" : null;
  const vips = has("bin.vips");
  const flavor = fields.get("stat");
  const statFlavor: StatFlavor =
    flavor === "gnu" || flavor === "bsd" ? flavor : "none";

  return {
    tier: python3 ? "python" : "shell",
    python3,
    pil,
    magick,
    vips,
    statFlavor,
    uname: fields.get("uname") ?? "",
    // Ordered by how little the host has to do: PIL resizes in the helper we
    // are already running, the others cost another process.
    resize: pil ? "pil" : magick !== null ? "magick" : vips ? "vips" : "none",
  };
}

/** One line for the panel's connection summary. */
export function describeCapabilities(caps: Capabilities): string {
  const resize =
    caps.resize === "pil"
      ? "resizes with Pillow"
      : caps.resize === "magick"
        ? `resizes with ImageMagick (${caps.magick})`
        : caps.resize === "vips"
          ? "resizes with vips"
          : "cannot resize remotely — large images transfer whole";
  const tier =
    caps.tier === "python"
      ? "python helper"
      : `shell fallback (${caps.statFlavor} stat)`;
  return `${caps.uname || "unknown host"}: ${tier}, ${resize}`;
}
```

- [ ] **Step 4: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS

- [ ] **Step 5: Commit**

```bash
git add lib/probe.ts test/probe.test.ts
git commit -m "Probe what the far side can do, once per connection

The probe is key=value rather than remote JSON: easier to get right
under someone else's /bin/sh, and forgiving of a host that grows a
line we do not know about.

A test runs the script under a real /bin/sh and asserts it neither
mktemps nor redirects to a path, so the leave-no-trace rule is checked
rather than assumed."
```

---

### Task 5: The Python helper

The tier-A workhorse: listing, stat, head-read, whole-read, and resize, delivered on ssh's stdin so it never exists as a remote file.

**Files:**
- Create: `lib/helper.py`
- Create: `test/helper.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: `lib/helper.py`, invoked as `python3 - <op> <root> <relpath> [arg]`, where `op` is `list`, `stat`, `head`, `read`, or `resize`. Every invocation writes one JSON header line, then — for `head`, `read`, and `resize` — the raw payload bytes.

- [ ] **Step 1: Write the failing tests**

Create `test/helper.test.ts`. It runs the helper through the local `python3` exactly as ssh would deliver it — on stdin.

```ts
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync } from "node:fs";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { deepStrictEqual, ok, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";

const HELPER = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "..", "lib", "helper.py"),
  "utf8",
);

/** A tree with the shapes that break naive listers. */
const root = mkdtempSync(join(tmpdir(), "rf-helper-"));
mkdirSync(join(root, "sub"));
mkdirSync(join(root, "sub", "deep"));
writeFileSync(join(root, "plain.txt"), "hello\n");
writeFileSync(join(root, "with space.txt"), "spaced\n");
writeFileSync(join(root, "quote'and;semi.txt"), "tricky\n");
writeFileSync(join(root, "sub", "big.bin"), Buffer.alloc(5000, 7));
symlinkSync(join(root, "plain.txt"), join(root, "link.txt"));
const outside = mkdtempSync(join(tmpdir(), "rf-outside-"));
writeFileSync(join(outside, "secret.txt"), "no\n");
symlinkSync(outside, join(root, "escape"));

type Run = { header: any; body: Buffer };
function run(args: string[]): Run {
  const stdout = execFileSync("python3", ["-", ...args], {
    input: HELPER,
    maxBuffer: 64 * 1024 * 1024,
  });
  const nl = stdout.indexOf(0x0a);
  return {
    header: JSON.parse(stdout.subarray(0, nl).toString("utf8")),
    body: stdout.subarray(nl + 1),
  };
}

describe("helper list", () => {
  it("lists with type, size, and mtime", () => {
    const { header } = run(["list", root, "."]);
    strictEqual(header.ok, true);
    const byName = new Map(header.entries.map((e: any) => [e.name, e]));
    strictEqual(byName.get("plain.txt").type, "file");
    strictEqual(byName.get("plain.txt").size, 6);
    ok(byName.get("plain.txt").mtime > 0);
    strictEqual(byName.get("sub").type, "dir");
  });

  it("handles names with spaces, quotes, and semicolons", () => {
    const { header } = run(["list", root, "."]);
    const names = header.entries.map((e: any) => e.name);
    ok(names.includes("with space.txt"));
    ok(names.includes("quote'and;semi.txt"));
  });

  it("reports symlinks as links, with their target", () => {
    const { header } = run(["list", root, "."]);
    const link = header.entries.find((e: any) => e.name === "link.txt");
    strictEqual(link.type, "link");
    strictEqual(link.linkType, "file");
    ok(String(link.linkTarget).endsWith("plain.txt"));
  });

  it("descends into a subdirectory relative to the root", () => {
    const { header } = run(["list", root, "sub"]);
    strictEqual(header.ok, true);
    deepStrictEqual(header.entries.map((e: any) => e.name).sort(), ["big.bin", "deep"]);
  });
});

describe("helper confinement", () => {
  it("refuses to escape the root with ..", () => {
    const { header } = run(["list", root, "../.."]);
    strictEqual(header.ok, false);
    ok(/outside the root/i.test(header.error), header.error);
  });

  it("refuses an absolute path outside the root", () => {
    const { header } = run(["list", root, outside]);
    strictEqual(header.ok, false);
  });

  // The check exists because symlinks resolve on the far side, not here.
  it("refuses a symlink that points out of the root", () => {
    const { header } = run(["list", root, "escape"]);
    strictEqual(header.ok, false);
    ok(/outside the root/i.test(header.error));
  });

  it("allows a path that only looks like an escape", () => {
    const { header } = run(["list", root, "sub/../sub/deep"]);
    strictEqual(header.ok, true);
  });
});

describe("helper stat, head, and read", () => {
  it("stats a file", () => {
    const { header } = run(["stat", root, "plain.txt"]);
    strictEqual(header.ok, true);
    strictEqual(header.type, "file");
    strictEqual(header.size, 6);
    ok(String(header.realpath).endsWith("plain.txt"));
  });

  it("returns whole bytes for read", () => {
    const { header, body } = run(["read", root, "plain.txt"]);
    strictEqual(header.bytes, 6);
    strictEqual(body.toString("utf8"), "hello\n");
  });

  it("returns a prefix for head, and says it truncated", () => {
    const { header, body } = run(["head", root, "sub/big.bin", "100"]);
    strictEqual(body.length, 100);
    strictEqual(header.truncated, true);
    strictEqual(header.size, 5000);
  });

  it("does not mark a short file truncated", () => {
    const { header } = run(["head", root, "plain.txt", "100"]);
    strictEqual(header.truncated, false);
  });

  it("errors legibly on a missing path", () => {
    const { header } = run(["stat", root, "nope.txt"]);
    strictEqual(header.ok, false);
    ok(header.error.length > 0);
  });
});

describe("helper framing", () => {
  // Task 7 splits the reply on the first newline and parses the prefix as
  // JSON. A traceback would break that contract for every caller, so the
  // header has to survive inputs the helper never anticipated.
  it("still emits one JSON line for a path containing a NUL byte", () => {
    // A real NUL byte can never reach the helper through `run()`: POSIX
    // exec() argv elements are NUL-terminated C strings, and Node's
    // child_process rejects an embedded NUL before it will even spawn
    // (verified directly: execFileSync throws ERR_INVALID_ARG_VALUE for a
    // string arg, and even a raw Buffer arg gets silently truncated at the
    // byte by the OS before python3 ever sees it). So this drives the same
    // guard a different way: build sys.argv inside the interpreter, where a
    // NUL-containing string can actually exist, and run the exact same
    // helper source through its own `__main__` gate.
    const driver = `
import sys
sys.argv = ["helper.py", "stat", ${JSON.stringify(root)}, "a" + chr(0) + "b"]
exec(compile(${JSON.stringify(HELPER)}, "helper.py", "exec"), {"__name__": "__main__"})
`;
    const stdout = execFileSync("python3", ["-c", driver], { maxBuffer: 64 * 1024 * 1024 });
    const nl = stdout.indexOf(0x0a);
    const header = JSON.parse(stdout.subarray(0, nl).toString("utf8"));
    strictEqual(header.ok, false);
    ok(String(header.error).length > 0);
  });

  it("still emits one JSON line for a non-numeric size argument", () => {
    const { header } = run(["head", root, "plain.txt", "not-a-number"]);
    strictEqual(header.ok, false);
    ok(/ValueError/.test(String(header.error)), String(header.error));
  });

  it("still emits one JSON line for an unknown operation", () => {
    const { header } = run(["frobnicate", root, "."]);
    strictEqual(header.ok, false);
  });
});

describe("helper hygiene", () => {
  it("writes nothing outside stdout", () => {
    const source = HELPER;
    ok(!/open\([^)]*['"][wax]/.test(source), "helper must not open files for writing");
    ok(!/tempfile|mkstemp|NamedTemporary/.test(source), "helper must not use tempfiles");
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — `ENOENT` reading `lib/helper.py`

- [ ] **Step 3: Implement `lib/helper.py`**

```python
# The tier-A remote helper for bb-plugin-remote-files.
#
# Delivered on ssh's stdin as `ssh <host> python3 - <op> <root> <rel> [arg]`,
# so it exists only in this process's memory: nothing is written to this
# machine's disk, and nothing is left behind when the process exits.
#
# Every invocation writes one JSON header line to stdout. For head, read, and
# resize the raw payload follows immediately after the newline, so the caller
# splits at the first \n and takes the rest as bytes.
#
# Written for Python 3.6 and up, standard library only, because the far side is
# whatever it happens to be. Pillow is used when present and never required.
import json
import os
import sys

BUF = 1 << 16


def emit(header, payload=None):
    """One JSON line, then optional raw bytes. Never anything else."""
    out = sys.stdout.buffer
    out.write(json.dumps(header).encode("utf-8"))
    out.write(b"\n")
    if payload is not None:
        out.write(payload)
    out.flush()


def fail(message):
    emit({"ok": False, "error": str(message)})
    sys.exit(0)  # The error is the answer; a non-zero exit would hide it.


def resolve(root, rel):
    """
    Resolve `rel` under `root` and prove the result is still inside it.

    realpath is what makes this meaningful: it runs here, where symlinks
    actually resolve, so a link pointing out of the root is caught. The same
    check performed on the calling side by string manipulation would not be.
    """
    real_root = os.path.realpath(root)
    target = rel if os.path.isabs(rel) else os.path.join(real_root, rel)
    real_target = os.path.realpath(target)
    if real_target != real_root and not real_target.startswith(real_root + os.sep):
        fail("Path resolves outside the root: %s" % real_target)
    return real_root, real_target


def kind(mode_stat):
    import stat as stat_mod

    if stat_mod.S_ISDIR(mode_stat.st_mode):
        return "dir"
    if stat_mod.S_ISREG(mode_stat.st_mode):
        return "file"
    return "other"


def describe(path, name):
    """One listing row. A broken symlink is a row, not an exception."""
    row = {"name": name, "type": "other", "size": 0, "mtime": 0,
           "linkTarget": None, "linkType": None, "mode": 0}
    try:
        lst = os.lstat(path)
    except OSError as exc:
        row["error"] = str(exc)
        return row
    row["mode"] = lst.st_mode & 0o7777
    row["mtime"] = int(lst.st_mtime)
    import stat as stat_mod

    if stat_mod.S_ISLNK(lst.st_mode):
        row["type"] = "link"
        try:
            row["linkTarget"] = os.readlink(path)
            row["linkType"] = kind(os.stat(path))
            row["size"] = os.stat(path).st_size
        except OSError:
            row["linkType"] = "broken"
        return row
    row["type"] = kind(lst)
    row["size"] = lst.st_size
    return row


def op_list(root, rel):
    real_root, target = resolve(root, rel)
    if not os.path.isdir(target):
        fail("Not a directory: %s" % target)
    try:
        names = sorted(os.listdir(target))
    except OSError as exc:
        fail(exc)
        return
    entries = [describe(os.path.join(target, n), n) for n in names]
    emit({
        "ok": True,
        "realpath": target,
        "root": real_root,
        "relpath": os.path.relpath(target, real_root),
        "entries": entries,
    })


def op_stat(root, rel):
    _, target = resolve(root, rel)
    try:
        info = os.stat(target)
    except OSError as exc:
        fail(exc)
        return
    emit({"ok": True, "realpath": target, "type": kind(info),
          "size": info.st_size, "mtime": int(info.st_mtime),
          "mode": info.st_mode & 0o7777})


def op_bytes(root, rel, limit):
    """head and read share everything but the limit."""
    _, target = resolve(root, rel)
    try:
        size = os.stat(target).st_size
        with open(target, "rb") as handle:
            data = handle.read(limit) if limit is not None else handle.read()
    except OSError as exc:
        fail(exc)
        return
    emit({"ok": True, "realpath": target, "size": size,
          "bytes": len(data), "truncated": len(data) < size}, data)


def op_resize(root, rel, max_dim):
    """
    Downscale to fit max_dim, entirely in memory. Nothing is written to this
    machine; the resized bytes go straight out on stdout.
    """
    _, target = resolve(root, rel)
    try:
        from PIL import Image
    except ImportError:
        fail("Pillow is not installed on this host")
        return
    import io

    try:
        image = Image.open(target)
        image.thumbnail((max_dim, max_dim))
        if image.mode not in ("RGB", "L"):
            image = image.convert("RGB")
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=85)
    except Exception as exc:  # Pillow raises many unrelated types.
        fail("Could not resize: %s" % exc)
        return
    data = buffer.getvalue()
    emit({"ok": True, "realpath": target, "bytes": len(data),
          "mime": "image/jpeg", "resized": True,
          "width": image.size[0], "height": image.size[1]}, data)


def main(argv):
    if len(argv) < 3:
        fail("usage: <op> <root> <relpath> [arg]")
    op, root, rel = argv[0], argv[1], argv[2]
    extra = argv[3] if len(argv) > 3 else None
    if op == "list":
        op_list(root, rel)
    elif op == "stat":
        op_stat(root, rel)
    elif op == "head":
        op_bytes(root, rel, int(extra or BUF))
    elif op == "read":
        op_bytes(root, rel, None)
    elif op == "resize":
        op_resize(root, rel, int(extra or 2048))
    else:
        fail("Unknown operation: %s" % op)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except SystemExit:
        raise
    except BaseException as exc:
        # The one-JSON-line header is a contract the caller parses. An
        # uncaught traceback goes to stderr and leaves stdout empty, which
        # reads to the caller as "unreadable reply" rather than as the
        # specific thing that went wrong. Every exit through here is still
        # one JSON line.
        fail("%s: %s" % (type(exc).__name__, exc))
```

- [ ] **Step 4: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS. If `python3` is absent locally, install it — the tier-A path cannot be developed without it.

- [ ] **Step 5: Commit**

```bash
git add lib/helper.py test/helper.test.ts
git commit -m "Add the remote helper, and confine paths where symlinks resolve

The helper is delivered on ssh's stdin, so it lives only in that
process's memory: nothing lands on the far side and nothing is left to
clean up. A test asserts it opens no file for writing and imports no
tempfile module, so that stays true.

Confinement runs remotely on purpose. A symlink out of the root
resolves there and nowhere else, so the same check done locally by
string comparison would pass a path that escapes."
```

---

### Task 6: The shell fallback tier

Hosts without `python3` still list and read. This tier is less capable and says so.

**Files:**
- Create: `lib/shell-tier.ts`
- Create: `test/shell-tier.test.ts`

**Interfaces:**
- Consumes: `StatFlavor` from `lib/probe.ts`.
- Produces:
  - `type Entry = { name: string; type: "file" | "dir" | "link" | "other"; size: number; mtime: number; linkTarget: string | null; linkType: string | null; mode: number }`
  - `listCommand(flavor: StatFlavor, root: string, rel: string): string[]`
  - `parseListing(flavor: StatFlavor, stdout: string): Entry[]`
  - `confinementCommand(root: string, rel: string): string[]`
  - `parseConfinement(stdout: string): { ok: true; root: string; realpath: string } | { ok: false; error: string }`
  - `SHELL_TIER_CAVEAT: string`

`Entry` is the shape both tiers produce; Task 7 re-exports it as the single listing type.

- [ ] **Step 1: Write the failing tests**

Create `test/shell-tier.test.ts`:

```ts
import { ok, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";
import {
  SHELL_TIER_CAVEAT,
  confinementCommand,
  listCommand,
  parseConfinement,
  parseListing,
} from "../lib/shell-tier.ts";

// Captured from `find . -maxdepth 1 -mindepth 1 -print0 | xargs -0 stat -c ...`
// on Debian 12 (GNU coreutils 9.1).
const GNU = [
  "81a4|6|1757260800|./plain.txt",
  "41ed|4096|1757260700|./sub",
  "a1ff|11|1757260600|./link.txt",
  "81a4|12|1757260500|./with space.txt",
].join("\n");

// Captured from the same pipeline on macOS 14 (BSD stat).
const BSD = [
  "81a4|6|1757260800|./plain.txt",
  "41ed|128|1757260700|./sub",
  "a1ff|11|1757260600|./link.txt",
].join("\n");

describe("listCommand", () => {
  // An empty directory must produce an empty listing, not a fabricated one.
  it("never lets stat run with zero operands", () => {
    const text = listCommand("gnu", "/srv/data", ".").join(" ");
    ok(!text.includes("xargs"), text);
    ok(text.includes("-exec"), text);
  });

  it("uses the GNU stat format on a GNU host", () => {
    const argv = listCommand("gnu", "/srv/data", "sub");
    ok(argv.join(" ").includes("-c"), "GNU stat takes -c");
    ok(argv.join(" ").includes("%f|%s|%Y|%n"));
  });

  it("uses the BSD stat format on a BSD host", () => {
    const argv = listCommand("bsd", "/srv/data", "sub");
    ok(argv.join(" ").includes("-f"), "BSD stat takes -f");
    ok(argv.join(" ").includes("%Xp|%z|%m|%N"));
  });

  // Paths go into the command as words for Task 2's shellQuote, never
  // pre-interpolated here — this function must not build a shell string.
  it("returns words, with the paths as their own elements", () => {
    const argv = listCommand("gnu", "/srv/my data", "a b");
    ok(argv.some((word) => word.includes("/srv/my data")), argv.join(" | "));
  });
});

describe("parseListing", () => {
  it("reads the GNU capture", () => {
    const entries = parseListing("gnu", GNU);
    strictEqual(entries.length, 4);
    const byName = new Map(entries.map((e) => [e.name, e]));
    strictEqual(byName.get("plain.txt")?.type, "file");
    strictEqual(byName.get("plain.txt")?.size, 6);
    strictEqual(byName.get("plain.txt")?.mtime, 1757260800);
    strictEqual(byName.get("sub")?.type, "dir");
    strictEqual(byName.get("link.txt")?.type, "link");
    strictEqual(byName.get("with space.txt")?.type, "file");
  });

  it("reads the BSD capture identically", () => {
    const entries = parseListing("bsd", BSD);
    strictEqual(entries.length, 3);
    strictEqual(entries.find((e) => e.name === "sub")?.type, "dir");
  });

  it("strips the leading ./ that find emits", () => {
    ok(parseListing("gnu", GNU).every((e) => !e.name.startsWith("./")));
  });

  it("keeps a name containing the field separator whole", () => {
    const entries = parseListing("gnu", "81a4|3|1757260800|./a|b.txt");
    strictEqual(entries.length, 1);
    strictEqual(entries[0]?.name, "a|b.txt");
  });

  it("skips malformed lines rather than throwing", () => {
    const entries = parseListing("gnu", `${GNU}\ngarbage\n\n`);
    strictEqual(entries.length, 4);
  });

  it("sorts by name so both tiers agree on order", () => {
    const names = parseListing("gnu", GNU).map((e) => e.name);
    ok(names.join() === [...names].sort().join(), names.join());
  });
});

describe("confinement", () => {
  it("resolves both paths with pwd -P", () => {
    const argv = confinementCommand("/srv/data", "sub");
    ok(argv.join(" ").includes("pwd -P"));
  });

  // `cd` fails on a regular file, so a cd-only script could not confine — and
  // therefore could not read — any file on this tier.
  it("has a path for a target that is not a directory", () => {
    const text = confinementCommand("/srv/data", "a.txt").join(" ");
    ok(text.includes("dirname"), text);
    ok(text.includes("basename"), text);
    ok(text.includes("-L"), "must detect a symlinked file");
  });

  it("passes root and rel as separate words, never interpolated", () => {
    const argv = confinementCommand("/srv/my data", "a b.txt");
    strictEqual(argv.at(-2), "/srv/my data");
    strictEqual(argv.at(-1), "a b.txt");
    ok(!argv[2]?.includes("/srv/my data"), "path must not reach the script text");
  });

  it("accepts a path inside the root", () => {
    const result = parseConfinement("/srv/data\n/srv/data/sub\n");
    strictEqual(result.ok, true);
    if (result.ok) strictEqual(result.realpath, "/srv/data/sub");
  });

  it("accepts the root itself", () => {
    strictEqual(parseConfinement("/srv/data\n/srv/data\n").ok, true);
  });

  it("refuses a sibling whose path merely shares a prefix", () => {
    strictEqual(parseConfinement("/srv/data\n/srv/data-other/x\n").ok, false);
  });

  // A root of "/" is legitimate, and `${root}/` would be "//" — which no real
  // path starts with, so every child would be refused.
  it("accepts children of a root of /", () => {
    strictEqual(parseConfinement("/\n/etc\n").ok, true);
    strictEqual(parseConfinement("/\n/\n").ok, true);
  });

  it("tolerates a root given with a trailing slash", () => {
    strictEqual(parseConfinement("/srv/data/\n/srv/data/sub\n").ok, true);
  });

  it("survives CRLF line endings", () => {
    strictEqual(parseConfinement("/srv/data\r\n/srv/data/sub\r\n").ok, true);
  });

  it("refuses a resolved path outside the root", () => {
    const result = parseConfinement("/srv/data\n/etc\n");
    strictEqual(result.ok, false);
    if (!result.ok) ok(/outside the root/i.test(result.error));
  });

  it("refuses output the shell never completed", () => {
    strictEqual(parseConfinement("/srv/data\n").ok, false);
  });

  // The marker is spliced into an argv, so it must survive spawn(). A NUL
  // byte cannot: POSIX exec() argv elements are NUL-terminated.
  it("uses a marker that can actually travel in an argv", () => {
    const text = confinementCommand("/srv/data", "a.txt").join(" ");
    strictEqual(text.includes("\u0000"), false, "a NUL byte cannot reach spawn()");
  });

  it("explains a symlinked file rather than calling it an escape", () => {
    const result = parseConfinement("/srv/data\n!symlink\n");
    strictEqual(result.ok, false);
    if (!result.ok) ok(/symlinked file/i.test(result.error), result.error);
  });
});

describe("SHELL_TIER_CAVEAT", () => {
  // The caveat is shown to the user, and an inaccurate caveat is worse than
  // none. Every limitation it names must be one this tier actually has.
  it("names each limitation this tier actually has", () => {
    ok(/newline/i.test(SHELL_TIER_CAVEAT));
    ok(/symlink/i.test(SHELL_TIER_CAVEAT));
    ok(/python/i.test(SHELL_TIER_CAVEAT), "must say why resizing is unavailable");
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — `Cannot find module '../lib/shell-tier.ts'`

- [ ] **Step 3: Implement `lib/shell-tier.ts`**

```ts
// The fallback for hosts without python3. Everything here is shaped by one
// fact: without an interpreter, structured output has to be parsed out of
// text, and text has no way to escape a filename containing its separator.
import type { StatFlavor } from "./probe.ts";

export type Entry = {
  name: string;
  type: "file" | "dir" | "link" | "other";
  size: number;
  mtime: number;
  linkTarget: string | null;
  linkType: string | null;
  mode: number;
};

/**
 * What this tier cannot do. Shown in the panel rather than hidden, because a
 * silently missing file is worse than an admitted limitation.
 */
export const SHELL_TIER_CAVEAT =
  "This host has no python3, so listings come from find and stat. Files whose " +
  "names contain a newline are not shown, symlink targets are not resolved, " +
  "large images transfer whole — remote resizing runs inside the python " +
  "helper, so it is unavailable here even if the host has ImageMagick — and " +
  "a symlinked file cannot be opened, only a real one.";

/**
 * `find | xargs stat`, with the stat format the probe says this host takes.
 * Returned as words so the caller can shellQuote each one; building a shell
 * string here would put the caller's quoting rule out of reach.
 *
 * The mode is asked for in hex (%f / %Xp) because that carries the file type
 * bits, which is how the type is recovered without a second call.
 */
export function listCommand(flavor: StatFlavor, root: string, rel: string): string[] {
  const format = flavor === "bsd" ? "%Xp|%z|%m|%N" : "%f|%s|%Y|%n";
  const flag = flavor === "bsd" ? "-f" : "-c";
  return [
    "sh",
    "-c",
    // `-exec ... {} +` rather than a pipe into xargs. With no matches xargs
    // still runs stat once with zero operands, and BSD stat then stats its
    // own stdin and prints a record for a file called "(stdin)" — a phantom
    // entry in every empty directory, with a zero exit code to hide it.
    // find's -exec simply does not invoke the utility when nothing matched.
    `cd -- "$1" && cd -- "$2" && find . -maxdepth 1 -mindepth 1 ` +
      `-exec stat ${flag} '${format}' {} +`,
    "sh",
    root,
    rel,
  ];
}

/** S_IFMT, from the high bits of the hex mode. */
function typeOf(modeHex: string): Entry["type"] {
  const mode = Number.parseInt(modeHex, 16);
  if (!Number.isFinite(mode)) return "other";
  switch (mode & 0o170000) {
    case 0o040000: return "dir";
    case 0o100000: return "file";
    case 0o120000: return "link";
    default: return "other";
  }
}

/**
 * Parse the stat output. The name is last and taken as the whole remainder, so
 * a name containing the separator survives; a name containing a newline does
 * not, and cannot, which is what SHELL_TIER_CAVEAT admits.
 */
export function parseListing(_flavor: StatFlavor, stdout: string): Entry[] {
  const entries: Entry[] = [];
  for (const line of stdout.split("\n")) {
    if (line.trim() === "") continue;
    const parts = line.split("|");
    if (parts.length < 4) continue;
    const [modeHex, sizeText, mtimeText] = parts;
    const rawName = parts.slice(3).join("|");
    const name = rawName.replace(/^\.\//, "");
    if (name === "") continue;
    const size = Number(sizeText);
    const mtime = Number(mtimeText);
    if (!Number.isFinite(size) || !Number.isFinite(mtime)) continue;
    if (size < 0 || mtime < 0) continue;
    entries.push({
      name,
      type: typeOf(modeHex ?? ""),
      size,
      mtime,
      // Neither is available without a per-entry readlink, and this tier is
      // already paying for one process per listing.
      linkTarget: null,
      linkType: null,
      mode: Number.parseInt(modeHex ?? "0", 16) & 0o7777,
    });
  }
  return entries.sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Resolve the root and the requested path with `cd`+`pwd -P`, which is POSIX
 * and follows symlinks — `readlink -f` is not portable to BSD.
 */
export function confinementCommand(root: string, rel: string): string[] {
  return [
    "sh",
    "-c",
    // `cd` resolves a directory, and a symlink to a directory, which is what
    // makes the check meaningful. But it fails outright on a regular file, so
    // a plain `cd -- "$2"` could not confine — or therefore read — any file at
    // all on this tier.
    //
    // So: try `cd` first, and fall back to resolving the parent and appending
    // the name. A symlinked *file* is refused rather than followed: resolving
    // one portably would mean chasing hops by hand, and this tier exists
    // precisely because the host has no interpreter to do that safely.
    `r=$(cd -- "$1" && pwd -P) || exit 1; ` +
      `if p=$(cd -- "$1" && cd -- "$2" 2>/dev/null && pwd -P); then ` +
      `printf '%s\\n%s\\n' "$r" "$p"; ` +
      `else ` +
      `d=$(cd -- "$1" && cd -- "$(dirname -- "$2")" && pwd -P) || exit 1; ` +
      `b=$(basename -- "$2"); ` +
      `if [ -L "$d/$b" ]; then printf '%s\\n%s\\n' "$r" "${SYMLINK_MARKER}"; ` +
      `else printf '%s\\n%s/%s\\n' "$r" "$d" "$b"; fi; fi`,
    "sh",
    root,
    rel,
  ];
}

/**
 * Stands in for a realpath the shell tier declines to resolve.
 *
 * It has no leading slash, and the value it is compared against always comes
 * from `pwd -P`, which is always absolute — so this can never collide with a
 * real answer. Deliberately not a NUL byte: this string is spliced into an
 * argv, and POSIX exec() argv elements are NUL-terminated, so Node refuses to
 * spawn at all if one appears.
 */
const SYMLINK_MARKER = "!symlink";

export function parseConfinement(
  stdout: string,
): { ok: true; root: string; realpath: string } | { ok: false; error: string } {
  // \r is stripped in case a host's shell terminates lines with CRLF; the
  // whole check is a string comparison and a stray \r would fail it.
  const [root, realpath] = stdout.split("\n").map((line) => line.replace(/\r$/, ""));
  if (!root || !realpath) {
    return { ok: false, error: "The host did not resolve the path." };
  }
  if (realpath === SYMLINK_MARKER) {
    return {
      ok: false,
      error:
        "This host has no python3, so a symlinked file cannot be followed " +
        "safely. Open it through its real path instead.",
    };
  }
  // The trailing separator is what makes this a path-segment comparison:
  // without it "/srv/data-other" passes as a child of "/srv/data". Building
  // it by hand rather than concatenating also handles a root of "/", where
  // `${root}/` would be "//" and no real path could ever match it.
  const prefix = root.endsWith("/") ? root : `${root}/`;
  if (realpath !== root && !realpath.startsWith(prefix)) {
    return { ok: false, error: `Path resolves outside the root: ${realpath}` };
  }
  return { ok: true, root, realpath };
}
```

- [ ] **Step 4: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS

- [ ] **Step 5: Commit**

```bash
git add lib/shell-tier.ts test/shell-tier.test.ts
git commit -m "Add the shell fallback tier for hosts without python3

Parsed against captures from GNU coreutils and BSD stat, including the
prefix case that a naive startsWith confinement check would let
through: /srv/data-other is not inside /srv/data.

The tier cannot represent a filename containing a newline. That is
stated in SHELL_TIER_CAVEAT and shown in the panel rather than hidden,
since a silently missing file is the worse failure."
```

---

### Task 7: The tier-agnostic remote client

One object the rest of the plugin talks to. It owns the ssh target, the probe result, and the choice of tier — so nothing above it ever branches on which tier is live.

**Files:**
- Create: `lib/remote.ts`
- Create: `test/remote.test.ts`
- Modify: `lib/shell-tier.ts` (add `statCommand` and `parseStat`)
- Modify: `test/shell-tier.test.ts` (cover them)

**Interfaces:**
- Consumes: `lib/target.ts`, `lib/ssh-argv.ts`, `lib/ssh-run.ts`, `lib/probe.ts`, `lib/shell-tier.ts`, `lib/helper.py`.
- Produces:
  - `type RemoteConfig = { sshTarget: string; rootDir: string; sshBin?: string }`
  - `type ConnectResult = { ok: true; capabilities: Capabilities } | { ok: false; error: string }`
  - `class RemoteClient` with:
    - `constructor(config: RemoteConfig)`
    - `connect(): Promise<ConnectResult>`
    - `capabilities: Capabilities | null`
    - `list(rel: string): Promise<{ ok: true; realpath: string; entries: Entry[] } | { ok: false; error: string }>`
    - `stat(rel: string): Promise<{ ok: true; realpath: string; type: string; size: number; mtime: number } | { ok: false; error: string }>`
    - `fetch(rel: string, opts: { limit?: number; resizeTo?: number }): Promise<{ ok: true; bytes: Buffer; truncated: boolean; resized: boolean; mime: string | null } | { ok: false; error: string }>`
  - `splitHeader(stdout: Buffer): { header: unknown; body: Buffer } | null`

- [ ] **Step 1: Write the failing tests**

Create `test/remote.test.ts`. It drives a fake `ssh` that executes the remote command locally, so both tiers run end to end without a network.

```ts
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ok, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";
import { RemoteClient, splitHeader } from "../lib/remote.ts";

/**
 * A fake ssh that ignores every option, takes the last argument as a shell
 * command, and runs it here. That is exactly what a real ssh does to the far
 * side, so both tiers get exercised for real.
 */
const bin = mkdtempSync(join(tmpdir(), "rf-remote-bin-"));
const fakeSsh = join(bin, "ssh");
writeFileSync(
  fakeSsh,
  `#!/bin/sh\nfor last in "$@"; do :; done\nexec /bin/sh -c "$last"\n`,
);
chmodSync(fakeSsh, 0o755);

const root = mkdtempSync(join(tmpdir(), "rf-remote-"));
mkdirSync(join(root, "sub"));
writeFileSync(join(root, "a.txt"), "alpha\n");
writeFileSync(join(root, "sub", "b.txt"), "beta\n");
// A directory outside the root, and a symlink into it. Confinement exists for
// this case: the link resolves on the far side, so only a check performed
// there can catch it.
const outside = mkdtempSync(join(tmpdir(), "rf-remote-outside-"));
writeFileSync(join(outside, "secret.txt", ), "no\n");
symlinkSync(outside, join(root, "escape"));

function client() {
  return new RemoteClient({ sshTarget: "fake-host", rootDir: root, sshBin: fakeSsh });
}

describe("splitHeader", () => {
  it("splits at the first newline and keeps the body raw", () => {
    const result = splitHeader(Buffer.concat([
      Buffer.from(`{"ok":true}\n`, "utf8"),
      Buffer.from([0x00, 0x0a, 0xff]),
    ]));
    ok(result);
    strictEqual(result!.body.toString("hex"), "000aff");
  });

  it("returns null when there is no header line", () => {
    strictEqual(splitHeader(Buffer.from("no newline here")), null);
  });

  it("returns null on an unparseable header", () => {
    strictEqual(splitHeader(Buffer.from("not json\nbody")), null);
  });
});

describe("RemoteClient", () => {
  it("refuses to connect with an unusable target", async () => {
    const bad = new RemoteClient({ sshTarget: "-oProxyCommand=x", rootDir: root, sshBin: fakeSsh });
    const result = await bad.connect();
    strictEqual(result.ok, false);
  });

  it("connects and reports capabilities", async () => {
    const result = await client().connect();
    strictEqual(result.ok, true);
    if (result.ok) ok(["python", "shell"].includes(result.capabilities.tier));
  });

  it("lists the root", async () => {
    const remote = client();
    await remote.connect();
    const result = await remote.list(".");
    strictEqual(result.ok, true);
    if (result.ok) {
      const names = result.entries.map((e) => e.name).sort();
      ok(names.includes("a.txt"));
      ok(names.includes("sub"));
    }
  });

  it("lists a subdirectory", async () => {
    const remote = client();
    await remote.connect();
    const result = await remote.list("sub");
    strictEqual(result.ok, true);
    if (result.ok) strictEqual(result.entries[0]?.name, "b.txt");
  });

  it("refuses to list outside the root, on either tier", async () => {
    for (const tier of ["python", "shell"] as const) {
      const remote = client();
      await remote.connect();
      if (remote.capabilities !== null) remote.capabilities.tier = tier;
      strictEqual((await remote.list("../..")).ok, false, `${tier}: ..`);
      strictEqual((await remote.list("escape")).ok, false, `${tier}: symlink`);
    }
  });

  it("fetches whole bytes", async () => {
    const remote = client();
    await remote.connect();
    const result = await remote.fetch("a.txt", {});
    strictEqual(result.ok, true);
    if (result.ok) strictEqual(result.bytes.toString("utf8"), "alpha\n");
  });

  it("fetches a prefix and marks it truncated", async () => {
    const remote = client();
    await remote.connect();
    const result = await remote.fetch("a.txt", { limit: 3 });
    strictEqual(result.ok, true);
    if (result.ok) {
      strictEqual(result.bytes.toString("utf8"), "alp");
      strictEqual(result.truncated, true);
    }
  });

  // Confinement on the read path, not just the list path. Both tiers are
  // forced explicitly, because a machine with python3 would otherwise only
  // ever exercise one of the two branches.
  it("refuses to fetch a path outside the root, on either tier", async () => {
    for (const tier of ["python", "shell"] as const) {
      const remote = client();
      await remote.connect();
      if (remote.capabilities !== null) remote.capabilities.tier = tier;
      const viaDots = await remote.fetch("../../etc/passwd", {});
      strictEqual(viaDots.ok, false, `${tier}: .. escaped the root`);
      const viaLink = await remote.fetch("escape/secret.txt", {});
      strictEqual(viaLink.ok, false, `${tier}: symlink escaped the root`);
    }
  });

  it("refuses to stat a path outside the root, on either tier", async () => {
    for (const tier of ["python", "shell"] as const) {
      const remote = client();
      await remote.connect();
      if (remote.capabilities !== null) remote.capabilities.tier = tier;
      strictEqual(
        (await remote.stat("escape/secret.txt")).ok,
        false,
        `${tier}: symlink escaped the root`,
      );
    }
  });

  // The root is not among its own children, so a stat built from the parent's
  // listing could never answer for it.
  it("stats the root itself, on either tier", async () => {
    for (const tier of ["python", "shell"] as const) {
      const remote = client();
      await remote.connect();
      if (remote.capabilities !== null) remote.capabilities.tier = tier;
      const result = await remote.stat(".");
      strictEqual(result.ok, true, `${tier}: stat(".") failed`);
      if (result.ok) strictEqual(result.type, "dir", `${tier}: root is a dir`);
    }
  });

  it("stats a file in the root, on either tier", async () => {
    for (const tier of ["python", "shell"] as const) {
      const remote = client();
      await remote.connect();
      if (remote.capabilities !== null) remote.capabilities.tier = tier;
      const result = await remote.stat("a.txt");
      strictEqual(result.ok, true, `${tier}: stat("a.txt") failed`);
      if (result.ok) strictEqual(result.size, 6, `${tier}: size`);
    }
  });

  // The state that used to fool server.ts's status(): the probe succeeded, so
  // the tier is known, but the connection is not usable. Deriving "connected"
  // from `capabilities !== null` reported success for exactly this case.
  it("knows the tier but reports failure when the root is unusable", async () => {
    const remote = new RemoteClient({
      sshTarget: "fake-host",
      rootDir: join(root, "no-such-directory"),
      sshBin: fakeSsh,
    });
    const result = await remote.connect();
    strictEqual(result.ok, false, "an unusable root must not connect");
    ok(remote.capabilities !== null, "the probe ran, so the tier is known");
    if (!result.ok) ok(/start directory/i.test(result.error), result.error);
  });

  it("refuses every operation before connect", async () => {
    const result = await client().list(".");
    strictEqual(result.ok, false);
    if (!result.ok) ok(/connect/i.test(result.error));
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — `Cannot find module '../lib/remote.ts'`

- [ ] **Step 2b: Add `statCommand` and `parseStat` to `lib/shell-tier.ts`**

The shell tier needs to stat one path directly. Append to `lib/shell-tier.ts`:

```ts
/**
 * stat one path, rather than hunting for it in its parent's listing. A
 * directory never appears among its own children, so a listing-derived stat
 * cannot answer for "." — which is the root, the first thing anything asks
 * about.
 *
 * The path is prefixed with `./` inside the script so a name beginning with
 * `-` cannot be read as an option, and `--` is avoided because BSD stat does
 * not accept it.
 */
export function statCommand(flavor: StatFlavor, root: string, rel: string): string[] {
  const format = flavor === "bsd" ? "%Xp|%z|%m|%N" : "%f|%s|%Y|%n";
  const flag = flavor === "bsd" ? "-f" : "-c";
  return [
    "sh",
    "-c",
    `cd -- "$1" && stat ${flag} '${format}' "./$2"`,
    "sh",
    root,
    rel,
  ];
}

/** The type, size, and mtime from one `statCommand` line. */
export function parseStat(
  flavor: StatFlavor,
  stdout: string,
): { type: Entry["type"]; size: number; mtime: number } | null {
  const line = stdout.split("\n").find((candidate) => candidate.trim() !== "");
  if (line === undefined) return null;
  const parts = line.split("|");
  if (parts.length < 4) return null;
  const size = Number(parts[1]);
  const mtime = Number(parts[2]);
  if (!Number.isFinite(size) || !Number.isFinite(mtime)) return null;
  if (size < 0 || mtime < 0) return null;
  return { type: typeOf(parts[0] ?? ""), size, mtime };
}
```

Add to `test/shell-tier.test.ts`:

```ts
describe("statCommand and parseStat", () => {
  it("neutralises a leading dash without using --", () => {
    const text = statCommand("gnu", "/srv/data", "-weird").join(" ");
    ok(text.includes(`"./$2"`), text);
    ok(!text.includes("--  "), "BSD stat does not accept --");
  });

  it("reads one stat line", () => {
    deepStrictEqual(parseStat("gnu", "41ed|4096|1757260700|./sub\n"), {
      type: "dir",
      size: 4096,
      mtime: 1757260700,
    });
  });

  it("returns null on empty or malformed output", () => {
    strictEqual(parseStat("gnu", ""), null);
    strictEqual(parseStat("gnu", "garbage\n"), null);
    strictEqual(parseStat("gnu", "41ed|x|y|./sub\n"), null);
  });
});
```

- [ ] **Step 3: Implement `lib/remote.ts`**

```ts
// The tier-agnostic remote client. Everything above this file — RPC handlers,
// HTTP routes, CLI — sees one interface and never learns whether the host runs
// the python helper or the shell fallback.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PROBE_SCRIPT, parseProbe, type Capabilities } from "./probe.ts";
import {
  confinementCommand,
  listCommand,
  parseConfinement,
  parseListing,
  parseStat,
  statCommand,
  type Entry,
} from "./shell-tier.ts";
import { buildSshArgv, controlSocketPath } from "./ssh-argv.ts";
import { classifySshFailure, runSsh } from "./ssh-run.ts";
import { parseTarget, type SshTarget } from "./target.ts";

export type { Entry };

/**
 * The helper source, read once at load. It ships as a .py file so it can be
 * edited, linted, and tested as Python, and travels to the far side on ssh's
 * stdin so it never becomes a file there.
 */
const HELPER_SOURCE = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "helper.py"),
  "utf8",
);

export type RemoteConfig = { sshTarget: string; rootDir: string; sshBin?: string };
export type ConnectResult =
  | { ok: true; capabilities: Capabilities }
  | { ok: false; error: string };
type Failure = { ok: false; error: string };

/** Split the helper's `<json header>\n<raw bytes>` framing. */
export function splitHeader(
  stdout: Buffer,
): { header: Record<string, unknown>; body: Buffer } | null {
  const newline = stdout.indexOf(0x0a);
  if (newline === -1) return null;
  try {
    const header = JSON.parse(stdout.subarray(0, newline).toString("utf8"));
    // typeof [] is "object", and an array header would pass every later
    // property read as undefined rather than failing here.
    if (header === null || typeof header !== "object" || Array.isArray(header)) {
      return null;
    }
    return { header, body: stdout.subarray(newline + 1) };
  } catch {
    return null;
  }
}

export class RemoteClient {
  readonly config: RemoteConfig;
  capabilities: Capabilities | null = null;
  private target: SshTarget | null = null;

  constructor(config: RemoteConfig) {
    this.config = config;
  }

  private async run(opts: {
    remote: string[];
    stdin?: string;
    timeoutMs?: number;
    maxBytes?: number;
  }): Promise<{ ok: true; stdout: Buffer } | Failure> {
    if (this.target === null) return { ok: false, error: "Not connected." };
    const result = await runSsh({
      argv: buildSshArgv({
        target: this.target,
        controlPath: controlSocketPath(this.target),
        remote: opts.remote,
      }),
      stdin: opts.stdin,
      timeoutMs: opts.timeoutMs,
      maxBytes: opts.maxBytes,
      sshBin: this.config.sshBin,
    });
    const failure = classifySshFailure(result);
    if (failure !== null) return { ok: false, error: failure };
    return { ok: true, stdout: result.stdout };
  }

  async connect(): Promise<ConnectResult> {
    const parsed = parseTarget(this.config.sshTarget);
    if (!parsed.ok) return { ok: false, error: parsed.error };
    this.target = parsed.target;

    if (this.config.rootDir.trim() === "") {
      this.target = null;
      return { ok: false, error: "A start directory is required." };
    }

    const probe = await this.run({ remote: ["sh", "-c", PROBE_SCRIPT], timeoutMs: 20_000 });
    if (!probe.ok) {
      this.target = null;
      return probe;
    }
    const capabilities = parseProbe(probe.stdout.toString("utf8"));

    // Reachability is not enough: a wrong start directory should read as a
    // wrong start directory, not as a broken connection.
    const rootCheck = await this.list(".");
    if (!rootCheck.ok) {
      this.capabilities = capabilities;
      return { ok: false, error: `Connected, but the start directory is unusable. ${rootCheck.error}` };
    }
    this.capabilities = capabilities;
    return { ok: true, capabilities };
  }

  /** Tier A: one helper invocation. The op's arguments follow the script. */
  private helper(op: string, rel: string, extra?: string): string[] {
    return [
      "python3", "-", op, this.config.rootDir, rel,
      ...(extra === undefined ? [] : [extra]),
    ];
  }

  async list(
    rel: string,
  ): Promise<{ ok: true; realpath: string; entries: Entry[] } | Failure> {
    if (this.capabilities?.tier === "shell") return this.listViaShell(rel);
    const result = await this.run({
      remote: this.helper("list", rel),
      stdin: HELPER_SOURCE,
    });
    if (!result.ok) return result;
    const split = splitHeader(result.stdout);
    if (split === null) {
      return { ok: false, error: `Unreadable reply from the host: ${result.stdout.subarray(0, 400).toString("utf8")}` };
    }
    const header = split.header as {
      ok?: boolean; error?: string; realpath?: string; entries?: Entry[];
    };
    if (header.ok !== true) return { ok: false, error: header.error ?? "The host refused the path." };
    return { ok: true, realpath: header.realpath ?? rel, entries: header.entries ?? [] };
  }

  private async listViaShell(
    rel: string,
  ): Promise<{ ok: true; realpath: string; entries: Entry[] } | Failure> {
    const flavor = this.capabilities?.statFlavor ?? "gnu";
    const confined = await this.run({ remote: confinementCommand(this.config.rootDir, rel) });
    if (!confined.ok) return confined;
    const check = parseConfinement(confined.stdout.toString("utf8"));
    if (!check.ok) return check;

    const listed = await this.run({ remote: listCommand(flavor, this.config.rootDir, rel) });
    if (!listed.ok) return listed;
    return {
      ok: true,
      realpath: check.realpath,
      entries: parseListing(flavor, listed.stdout.toString("utf8")),
    };
  }

  async stat(
    rel: string,
  ): Promise<
    { ok: true; realpath: string; type: string; size: number; mtime: number } | Failure
  > {
    if (this.capabilities?.tier === "shell") {
      const flavor = this.capabilities.statFlavor;
      const confined = await this.run({
        remote: confinementCommand(this.config.rootDir, rel),
      });
      if (!confined.ok) return confined;
      const check = parseConfinement(confined.stdout.toString("utf8"));
      if (!check.ok) return check;

      // stat the path itself rather than hunting for it in its parent's
      // listing. The listing approach cannot answer for "." — no directory
      // appears among its own children — so it failed on the root, and on any
      // path with a trailing slash, on exactly the hosts where the python
      // helper is unavailable to cover for it.
      const statted = await this.run({
        remote: statCommand(flavor, this.config.rootDir, rel),
      });
      if (!statted.ok) return statted;
      const info = parseStat(flavor, statted.stdout.toString("utf8"));
      if (info === null) return { ok: false, error: `No such path: ${rel}` };
      return { ok: true, realpath: check.realpath, ...info };
    }
    const result = await this.run({ remote: this.helper("stat", rel), stdin: HELPER_SOURCE });
    if (!result.ok) return result;
    const split = splitHeader(result.stdout);
    if (split === null) return { ok: false, error: "Unreadable reply from the host." };
    const header = split.header as {
      ok?: boolean; error?: string; realpath?: string; type?: string; size?: number; mtime?: number;
    };
    if (header.ok !== true) return { ok: false, error: header.error ?? "stat failed." };
    return {
      ok: true,
      realpath: header.realpath ?? rel,
      type: header.type ?? "other",
      size: header.size ?? 0,
      mtime: header.mtime ?? 0,
    };
  }

  async fetch(
    rel: string,
    opts: { limit?: number; resizeTo?: number },
  ): Promise<
    | { ok: true; bytes: Buffer; truncated: boolean; resized: boolean; mime: string | null }
    | Failure
  > {
    if (this.capabilities?.tier === "shell") {
      // No helper: dd gives a byte-exact prefix portably, cat gives the rest.
      const remote =
        opts.limit === undefined
          ? ["sh", "-c", `cd -- "$1" && cat -- "$2"`, "sh", this.config.rootDir, rel]
          // `head -c`, not `dd bs=1 count=N`: bs=1 costs one read syscall per
          // byte, so a 256KB text preview would make a quarter of a million
          // of them. head -c is not in POSIX but is present on GNU coreutils
          // and BSD alike, which is the whole population of this tier.
          : ["sh", "-c", `cd -- "$1" && head -c "$3" -- "$2"`, "sh", this.config.rootDir, rel, String(opts.limit)];
      const confined = await this.run({ remote: confinementCommand(this.config.rootDir, rel) });
      if (!confined.ok) return confined;
      const check = parseConfinement(confined.stdout.toString("utf8"));
      if (!check.ok) return check;
      const result = await this.run({ remote, timeoutMs: 120_000 });
      if (!result.ok) return result;
      return {
        ok: true,
        bytes: result.stdout,
        truncated: opts.limit !== undefined && result.stdout.length >= opts.limit,
        resized: false,
        mime: null,
      };
    }

    const wantsResize = opts.resizeTo !== undefined && this.capabilities?.resize === "pil";
    const remote = wantsResize
      ? this.helper("resize", rel, String(opts.resizeTo))
      : opts.limit === undefined
        ? this.helper("read", rel)
        : this.helper("head", rel, String(opts.limit));

    const result = await this.run({ remote, stdin: HELPER_SOURCE, timeoutMs: 120_000 });
    if (!result.ok) return result;
    const split = splitHeader(result.stdout);
    if (split === null) return { ok: false, error: "Unreadable reply from the host." };
    const header = split.header as {
      ok?: boolean; error?: string; bytes?: number; truncated?: boolean; resized?: boolean; mime?: string;
    };
    if (header.ok !== true) return { ok: false, error: header.error ?? "The read failed." };

    // ssh gives a clean binary pipe with -T, so a short body means something
    // went wrong on the wire rather than in the helper. Say so rather than
    // caching a truncated image.
    if (typeof header.bytes === "number" && split.body.length !== header.bytes) {
      return {
        ok: false,
        error: `Transfer was short: expected ${header.bytes} bytes, received ${split.body.length}.`,
      };
    }
    return {
      ok: true,
      bytes: split.body,
      truncated: header.truncated === true,
      resized: header.resized === true,
      mime: header.mime ?? null,
    };
  }
}
```

- [ ] **Step 4: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS

- [ ] **Step 5: Commit**

```bash
git add lib/remote.ts test/remote.test.ts
git commit -m "Add the tier-agnostic remote client

One interface over both tiers, so no RPC handler, HTTP route, or CLI
verb ever branches on whether the host has python3.

The fake ssh in the tests takes the last argument and runs it under
/bin/sh — which is what a real ssh does to the far side — so both
tiers are exercised end to end without a network.

Connect distinguishes a reachable host from a usable start directory,
because those are two different things for a user to fix."
```

---

### Task 8: The size policy

A pure decision table, separated from both the transport and the cache so every row is testable in isolation.

**Files:**
- Create: `lib/policy.ts`
- Create: `test/policy.test.ts`

**Interfaces:**
- Consumes: `Capabilities` from `lib/probe.ts`.
- Produces:
  - `SMALL_FILE_BYTES: number` (2 MB), `TEXT_HEAD_BYTES: number` (256 KB), `IMAGE_MAX_DIM: number` (2048)
  - `guessKind(name: string): "image" | "text" | "other"`
  - `type PlanAction = { kind: "whole" } | { kind: "head"; limit: number } | { kind: "resize"; maxDim: number } | { kind: "whole-then-resize-locally"; maxDim: number } | { kind: "refuse"; reason: string }`
  - `planFetch(input: { name: string; size: number; type: string; capabilities: Capabilities }): PlanAction`

- [ ] **Step 1: Write the failing tests**

Create `test/policy.test.ts`:

```ts
import { deepStrictEqual, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";
import type { Capabilities } from "../lib/probe.ts";
import { SMALL_FILE_BYTES, TEXT_HEAD_BYTES, guessKind, planFetch } from "../lib/policy.ts";

const withResize: Capabilities = {
  tier: "python", python3: true, pil: true, magick: null, vips: false,
  statFlavor: "gnu", uname: "Linux", resize: "pil",
};
const withoutResize: Capabilities = { ...withResize, pil: false, resize: "none" };

describe("guessKind", () => {
  it("recognises images", () => {
    for (const name of ["a.jpg", "a.JPEG", "a.png", "a.gif", "a.webp", "a.bmp", "a.tif"]) {
      strictEqual(guessKind(name), "image", name);
    }
  });

  it("recognises text and source", () => {
    for (const name of ["a.txt", "a.md", "a.ts", "a.py", "a.json", "a.log", "Makefile", "README"]) {
      strictEqual(guessKind(name), "text", name);
    }
  });

  // A dotfile's name IS its extension. These are in the text list for this
  // reason, so treating a leading dot as "no extension" would waste the entry.
  it("recognises a bare dotfile whose name is a known extension", () => {
    for (const name of [".gitignore", ".env", ".ts"]) {
      strictEqual(guessKind(name), "text", name);
    }
  });

  it("treats a trailing dot as no extension", () => {
    strictEqual(guessKind("archive."), "other");
  });

  it("calls everything else other", () => {
    for (const name of ["a.zip", "a.mp4", "a.so", "a.pdf"]) {
      strictEqual(guessKind(name), "other", name);
    }
  });
});

describe("planFetch", () => {
  const plan = (over: Partial<Parameters<typeof planFetch>[0]>) =>
    planFetch({ name: "a.txt", size: 10, type: "file", capabilities: withResize, ...over });

  it("takes a small file whole, whatever it is", () => {
    deepStrictEqual(plan({ name: "a.bin", size: SMALL_FILE_BYTES }), { kind: "whole" });
    deepStrictEqual(plan({ name: "a.jpg", size: SMALL_FILE_BYTES - 1 }), { kind: "whole" });
  });

  it("resizes a large image remotely when the host can", () => {
    deepStrictEqual(plan({ name: "a.jpg", size: SMALL_FILE_BYTES + 1 }), {
      kind: "resize",
      maxDim: 2048,
    });
  });

  it("falls back to a local resize when the host cannot", () => {
    deepStrictEqual(
      plan({ name: "a.jpg", size: SMALL_FILE_BYTES + 1, capabilities: withoutResize }),
      { kind: "whole-then-resize-locally", maxDim: 2048 },
    );
  });

  // The tier gate has to be load-bearing on its own. parseProbe only ever
  // sets pil when python3 is present, so a test using a probe-shaped value
  // passes just as well without the tier check — this uses the out-of-band
  // combination the type permits but the probe never emits, which is the only
  // input that can tell the two implementations apart.
  it("gates on the tier, not only on pil", () => {
    const impossibleFromProbe: Capabilities = {
      ...withResize, tier: "shell", python3: false, resize: "pil",
    };
    deepStrictEqual(
      plan({ name: "a.jpg", size: SMALL_FILE_BYTES + 1, capabilities: impossibleFromProbe }),
      { kind: "whole-then-resize-locally", maxDim: 2048 },
    );
  });

  // The probe reports what the host has; this reports what the plugin can
  // reach. A shell-tier host with ImageMagick has the tool and no way to use it.
  it("does not claim a remote resize the shell tier cannot reach", () => {
    const shellWithMagick: Capabilities = {
      ...withResize, tier: "shell", python3: false, pil: false,
      magick: "convert", resize: "magick",
    };
    deepStrictEqual(
      plan({ name: "a.jpg", size: SMALL_FILE_BYTES + 1, capabilities: shellWithMagick }),
      { kind: "whole-then-resize-locally", maxDim: 2048 },
    );
  });

  it("heads a large text file", () => {
    deepStrictEqual(plan({ name: "huge.log", size: 2e9 }), {
      kind: "head",
      limit: TEXT_HEAD_BYTES,
    });
  });

  it("refuses a large file that is neither text nor image", () => {
    const action = plan({ name: "a.mp4", size: 2e9 });
    strictEqual(action.kind, "refuse");
    if (action.kind === "refuse") strictEqual(action.reason.length > 0, true);
  });

  it("refuses a directory", () => {
    strictEqual(plan({ name: "sub", size: 4096, type: "dir" }).kind, "refuse");
  });

  it("refuses a device or socket", () => {
    strictEqual(plan({ name: "null", size: 0, type: "other" }).kind, "refuse");
  });

  it("treats the boundary as small, not large", () => {
    strictEqual(plan({ name: "a.jpg", size: SMALL_FILE_BYTES }).kind, "whole");
    strictEqual(plan({ name: "a.jpg", size: SMALL_FILE_BYTES + 1 }).kind, "resize");
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — `Cannot find module '../lib/policy.ts'`

- [ ] **Step 3: Implement `lib/policy.ts`**

```ts
// What to fetch, and how much of it. A pure decision table: the transport
// executes it and the cache stores the result, but the choice lives here so
// every row is testable without a host.
import type { Capabilities } from "./probe.ts";

/** Below this, transferring the whole file is cheaper than being clever. */
export const SMALL_FILE_BYTES = 2 * 1024 * 1024;
/** Enough of a log or a source file to be worth reading. */
export const TEXT_HEAD_BYTES = 256 * 1024;
/** Long edge of a preview image. Comfortably above any panel width. */
export const IMAGE_MAX_DIM = 2048;

const IMAGE_EXTENSIONS = new Set([
  "jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "avif", "heic", "ico",
]);
const TEXT_EXTENSIONS = new Set([
  "txt", "md", "markdown", "rst", "log", "json", "jsonl", "yaml", "yml", "toml",
  "ini", "cfg", "conf", "csv", "tsv", "xml", "html", "css", "js", "jsx", "ts",
  "tsx", "py", "rb", "go", "rs", "c", "h", "cc", "cpp", "hpp", "java", "kt",
  "sh", "bash", "zsh", "fish", "sql", "el", "lisp", "clj", "hs", "ml", "st",
  "diff", "patch", "env", "lock", "gitignore",
]);
/** Extensionless files that are conventionally text. */
const TEXT_NAMES = new Set([
  "readme", "license", "licence", "makefile", "dockerfile", "changelog",
  "authors", "copying", "notice", "todo", "install",
]);

export function guessKind(name: string): "image" | "text" | "other" {
  const lower = name.toLowerCase();
  const dot = lower.lastIndexOf(".");
  // A leading dot is an extension here, not the absence of one: ".gitignore"
  // and ".env" are both in the text list precisely so they read as text, and
  // treating them as extensionless would leave them classified "other". A
  // trailing dot really is no extension.
  const extension = dot < 0 || dot === lower.length - 1 ? "" : lower.slice(dot + 1);
  if (IMAGE_EXTENSIONS.has(extension)) return "image";
  if (TEXT_EXTENSIONS.has(extension)) return "text";
  if (extension === "" && TEXT_NAMES.has(lower)) return "text";
  return "other";
}

export type PlanAction =
  | { kind: "whole" }
  | { kind: "head"; limit: number }
  | { kind: "resize"; maxDim: number }
  | { kind: "whole-then-resize-locally"; maxDim: number }
  | { kind: "refuse"; reason: string };

export function planFetch(input: {
  name: string;
  size: number;
  type: string;
  capabilities: Capabilities;
}): PlanAction {
  if (input.type === "dir") {
    return { kind: "refuse", reason: "This is a directory." };
  }
  if (input.type !== "file" && input.type !== "link") {
    return { kind: "refuse", reason: "This is not a regular file." };
  }
  if (input.size <= SMALL_FILE_BYTES) return { kind: "whole" };

  switch (guessKind(input.name)) {
    case "image":
      // Resizing on the far side is the whole point: only the resized bytes
      // cross the wire. But it runs inside the python helper, so it needs the
      // python tier AND Pillow. A shell-tier host with ImageMagick still
      // reports resize: "magick" from the probe and nothing here can reach
      // it — calling that remote-capable would label a full-size transfer
      // "downscaled" in the UI. Without a reachable remote resize we still
      // show the image, we just pay for it once.
      return input.capabilities.tier === "python" && input.capabilities.resize === "pil"
        ? { kind: "resize", maxDim: IMAGE_MAX_DIM }
        : { kind: "whole-then-resize-locally", maxDim: IMAGE_MAX_DIM };
    case "text":
      return { kind: "head", limit: TEXT_HEAD_BYTES };
    default:
      return {
        kind: "refuse",
        reason: `${Math.round(input.size / 1024 / 1024)} MB, and not something this browser can preview.`,
      };
  }
}
```

- [ ] **Step 4: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS

- [ ] **Step 5: Commit**

```bash
git add lib/policy.ts test/policy.test.ts
git commit -m "Decide what to fetch, as a table rather than as branches

Every row is a test: small files whole, large images resized on the
far side when it can and locally when it cannot, large text headed,
anything else refused with its size rather than silently pulled."
```

---

### Task 9: The cache

Content-addressed blobs in `.cache/`, with a SQLite index and LRU eviction.

**Files:**
- Create: `lib/cache.ts`
- Create: `test/cache.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `cacheKey(input: { sshTarget: string; realpath: string; size: number; mtime: number; variant: string }): string`
  - `class BlobCache` with:
    - `constructor(dir: string, opts?: { maxBytes?: number })`
    - `path(key: string): string`
    - `get(key: string): { path: string; bytes: number; mime: string | null } | null`
    - `put(key: string, bytes: Buffer, meta: { mime: string | null; remotePath: string }): { path: string }`
    - `totalBytes(): number`
    - `prune(): number`
    - `clear(): void`
    - `close(): void`

- [ ] **Step 1: Write the failing tests**

Create `test/cache.test.ts`:

```ts
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { notStrictEqual, ok, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";
import { BlobCache, cacheKey } from "../lib/cache.ts";

const base = { sshTarget: "box", realpath: "/srv/a.jpg", size: 100, mtime: 5, variant: "raw" };

function freshCache(maxBytes?: number) {
  return new BlobCache(mkdtempSync(join(tmpdir(), "rf-cache-")), { maxBytes });
}

describe("cacheKey", () => {
  it("is stable for identical inputs", () => {
    strictEqual(cacheKey(base), cacheKey({ ...base }));
  });

  // Identity is the whole invalidation strategy: a changed file must miss.
  it("changes when any part of the file's identity changes", () => {
    for (const change of [
      { sshTarget: "other" },
      { realpath: "/srv/b.jpg" },
      { size: 101 },
      { mtime: 6 },
      { variant: "thumb-256" },
    ]) {
      notStrictEqual(cacheKey(base), cacheKey({ ...base, ...change }), JSON.stringify(change));
    }
  });

  it("is filesystem-safe hex", () => {
    ok(/^[0-9a-f]{64}$/.test(cacheKey(base)));
  });

  // A POSIX filename may contain any byte but NUL, so any separator we joined
  // on could also appear inside a field and let one identity impersonate
  // another. Length prefixes are what make the encoding unambiguous.
  it("cannot be collided by a field containing the separator", () => {
    for (const separator of [" ", "\n", "\t", "|", ":"]) {
      const left = cacheKey({ ...base, sshTarget: "host", realpath: `a${separator}b` });
      const right = cacheKey({ ...base, sshTarget: `host${separator}a`, realpath: "b" });
      notStrictEqual(left, right, `collided on ${JSON.stringify(separator)}`);
    }
  });
});

describe("BlobCache", () => {
  it("misses before anything is stored", () => {
    strictEqual(freshCache().get("deadbeef"), null);
  });

  it("stores and returns bytes with their mime", () => {
    const cache = freshCache();
    const key = cacheKey(base);
    cache.put(key, Buffer.from("hello"), { mime: "text/plain", remotePath: "/srv/a.txt" });
    const hit = cache.get(key);
    ok(hit);
    strictEqual(readFileSync(hit!.path, "utf8"), "hello");
    strictEqual(hit!.mime, "text/plain");
    strictEqual(hit!.bytes, 5);
  });

  it("shards blobs so one directory does not hold everything", () => {
    const cache = freshCache();
    const key = cacheKey(base);
    const { path } = cache.put(key, Buffer.from("x"), { mime: null, remotePath: "/srv/a" });
    ok(path.includes(join("blobs", key.slice(0, 2))), path);
  });

  // A blob deleted by hand must not read as a hit with a missing file.
  it("treats a vanished blob as a miss", () => {
    const cache = freshCache();
    const key = cacheKey(base);
    const { path } = cache.put(key, Buffer.from("x"), { mime: null, remotePath: "/srv/a" });
    rmSync(path);
    strictEqual(cache.get(key), null);
  });

  it("counts its total size", () => {
    const cache = freshCache();
    cache.put("a".repeat(64), Buffer.alloc(10), { mime: null, remotePath: "/a" });
    cache.put("b".repeat(64), Buffer.alloc(20), { mime: null, remotePath: "/b" });
    strictEqual(cache.totalBytes(), 30);
  });

  // Date.now() is milliseconds and these calls take microseconds, so a burst
  // of writes shares one timestamp. The ordering must come from a counter.
  it("evicts by last use even when every write lands in the same millisecond", () => {
    const cache = freshCache(100);
    cache.put("a".repeat(64), Buffer.alloc(40), { mime: null, remotePath: "/a" });
    cache.put("b".repeat(64), Buffer.alloc(40), { mime: null, remotePath: "/b" });
    cache.get("a".repeat(64));
    cache.put("c".repeat(64), Buffer.alloc(40), { mime: null, remotePath: "/c" });
    strictEqual(cache.get("b".repeat(64)), null, "b was least recently used");
    ok(cache.get("a".repeat(64)), "a was touched after b and must survive");
  });

  // A blob bigger than the whole cache used to evict itself on the way in and
  // hand back a path to a file that no longer existed.
  it("keeps a blob larger than the cap rather than deleting what it just wrote", () => {
    const cache = freshCache(50);
    const { path } = cache.put("a".repeat(64), Buffer.alloc(200), {
      mime: null,
      remotePath: "/big",
    });
    ok(existsSync(path), "put returned a path to a file it had already deleted");
    ok(cache.get("a".repeat(64)), "the entry it just wrote must be readable");
  });

  it("evicts least-recently-used entries past the cap", () => {
    const cache = freshCache(100);
    cache.put("a".repeat(64), Buffer.alloc(60), { mime: null, remotePath: "/a" });
    cache.put("b".repeat(64), Buffer.alloc(30), { mime: null, remotePath: "/b" });
    cache.get("a".repeat(64)); // touch a, so b is now the oldest
    cache.put("c".repeat(64), Buffer.alloc(30), { mime: null, remotePath: "/c" });
    strictEqual(cache.get("b".repeat(64)), null, "b should have been evicted");
    ok(cache.get("a".repeat(64)), "a was touched and should survive");
    ok(cache.get("c".repeat(64)), "c was just written");
    ok(cache.totalBytes() <= 100);
  });

  it("removes the file from disk when it evicts", () => {
    const cache = freshCache(50);
    const { path } = cache.put("a".repeat(64), Buffer.alloc(40), { mime: null, remotePath: "/a" });
    cache.put("b".repeat(64), Buffer.alloc(40), { mime: null, remotePath: "/b" });
    strictEqual(existsSync(path), false);
  });

  it("survives being reopened on the same directory", () => {
    const dir = mkdtempSync(join(tmpdir(), "rf-cache-reopen-"));
    const first = new BlobCache(dir);
    first.put("a".repeat(64), Buffer.from("kept"), { mime: null, remotePath: "/a" });
    first.close();
    const second = new BlobCache(dir);
    ok(second.get("a".repeat(64)), "entry should survive a reopen");
    second.close();
  });

  it("clears everything", () => {
    const cache = freshCache();
    cache.put("a".repeat(64), Buffer.alloc(10), { mime: null, remotePath: "/a" });
    cache.clear();
    strictEqual(cache.totalBytes(), 0);
    strictEqual(cache.get("a".repeat(64)), null);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — `Cannot find module '../lib/cache.ts'`

- [ ] **Step 3: Implement `lib/cache.ts`**

```ts
// The local blob cache. Lives in the plugin directory under .cache/, which is
// gitignored. better-sqlite3 is externalized by `bb plugin build` and resolved
// against bb's own copy at runtime.
import Database from "better-sqlite3";
import { createHash } from "node:crypto";
import { mkdirSync, rmSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

/**
 * A blob's identity. Size and mtime are part of the key rather than something
 * checked after a lookup, so a changed remote file simply misses. There is no
 * invalidation step, and therefore no invalidation bug.
 *
 * `variant` separates derivatives of one file — the original, a 2048px
 * preview, a 256px thumbnail — which would otherwise collide.
 */
export function cacheKey(input: {
  sshTarget: string;
  realpath: string;
  size: number;
  mtime: number;
  variant: string;
}): string {
  // Length-prefixed, not joined by a separator. A POSIX filename may contain
  // any byte but NUL — including whatever separator we might pick — so a plain
  // join lets two different identities produce one key: a realpath of "a b"
  // and a target ending in " a" with realpath "b" hash identically.
  const hash = createHash("sha256");
  for (const field of [
    input.sshTarget,
    input.realpath,
    String(input.size),
    String(input.mtime),
    input.variant,
  ]) {
    hash.update(`${Buffer.byteLength(field)}:${field}`);
  }
  return hash.digest("hex");
}

const DEFAULT_MAX_BYTES = 1024 * 1024 * 1024;

type Row = { key: string; bytes: number; mime: string | null };

export class BlobCache {
  private readonly db: Database.Database;
  private readonly dir: string;
  private readonly maxBytes: number;

  constructor(dir: string, opts?: { maxBytes?: number }) {
    this.dir = dir;
    this.maxBytes = opts?.maxBytes ?? DEFAULT_MAX_BYTES;
    mkdirSync(join(dir, "blobs"), { recursive: true });
    this.db = new Database(join(dir, "index.db"));
    this.db.pragma("journal_mode = WAL");

    // A cache written by an older version of this file lacks `seq`. It is a
    // cache: discarding it costs a re-fetch, and carrying a migration for
    // disposable data costs more than that forever.
    const columns = this.db.prepare("PRAGMA table_info(blobs)").all() as Array<{
      name: string;
    }>;
    if (columns.length > 0 && !columns.some((column) => column.name === "seq")) {
      this.db.exec("DROP TABLE blobs");
      rmSync(join(dir, "blobs"), { recursive: true, force: true });
      mkdirSync(join(dir, "blobs"), { recursive: true });
    }

    this.db.exec(`
      CREATE TABLE IF NOT EXISTS blobs (
        key         TEXT PRIMARY KEY,
        bytes       INTEGER NOT NULL,
        mime        TEXT,
        remote_path TEXT NOT NULL,
        accessed_at INTEGER NOT NULL,
        seq         INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS blobs_seq ON blobs (seq);
    `);

    // Least-recently-used has to be ordered by a counter, not by a clock.
    // Date.now() has millisecond resolution and these sqlite calls finish in
    // microseconds, so every entry in a burst shares one timestamp — and both
    // obvious tiebreaks are wrong: `key` orders by sha256 digest, which is
    // arbitrary, and ROWID survives an ON CONFLICT UPDATE unchanged, so it
    // records insertion order rather than last use.
    const highest = this.db
      .prepare("SELECT COALESCE(MAX(seq), 0) AS top FROM blobs")
      .get() as { top: number };
    this.seq = highest.top;
  }

  /** Monotonic within this handle, and resumed from the index on reopen. */
  private seq: number;

  private touch(): number {
    this.seq += 1;
    return this.seq;
  }

  /** Sharded by the first byte of the key: 256 directories, not one. */
  path(key: string): string {
    return join(this.dir, "blobs", key.slice(0, 2), key);
  }

  get(key: string): { path: string; bytes: number; mime: string | null } | null {
    const row = this.db.prepare("SELECT key, bytes, mime FROM blobs WHERE key = ?").get(key) as
      | Row
      | undefined;
    if (row === undefined) return null;
    const path = this.path(key);
    // The index is not the authority on what is on disk. Someone can delete
    // .cache/ by hand, and that should be a miss rather than a broken read.
    try {
      statSync(path);
    } catch {
      this.db.prepare("DELETE FROM blobs WHERE key = ?").run(key);
      return null;
    }
    this.db
      .prepare("UPDATE blobs SET accessed_at = ?, seq = ? WHERE key = ?")
      .run(Date.now(), this.touch(), key);
    return { path, bytes: row.bytes, mime: row.mime };
  }

  put(
    key: string,
    bytes: Buffer,
    meta: { mime: string | null; remotePath: string },
  ): { path: string } {
    const path = this.path(key);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, bytes);
    try {
      this.db
        .prepare(
          `INSERT INTO blobs (key, bytes, mime, remote_path, accessed_at, seq)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(key) DO UPDATE SET
             bytes = excluded.bytes,
             mime = excluded.mime,
             accessed_at = excluded.accessed_at,
             seq = excluded.seq`,
        )
        .run(key, bytes.length, meta.mime, meta.remotePath, Date.now(), this.touch());
    } catch (cause) {
      // The file is written but unindexed, so nothing would ever count it or
      // evict it. Remove it rather than leak it.
      try {
        unlinkSync(path);
      } catch {
        /* the blob was already gone; the index write is the real failure */
      }
      throw cause;
    }
    this.prune(key);
    return { path };
  }

  totalBytes(): number {
    const row = this.db.prepare("SELECT COALESCE(SUM(bytes), 0) AS total FROM blobs").get() as {
      total: number;
    };
    return row.total;
  }

  /**
   * Drop least-recently-used entries until the cache fits. Returns the count.
   *
   * `keep` is the key just written, which is never evicted: a blob larger than
   * the whole cap would otherwise delete itself on the way in and hand its
   * caller a path to a file that no longer exists. The cache is then over its
   * cap by at most one blob, until the next put.
   */
  prune(keep?: string): number {
    let total = this.totalBytes();
    if (total <= this.maxBytes) return 0;
    // .all(), not .iterate(): better-sqlite3 refuses a write on a connection
    // with an open cursor, and this loop deletes as it goes.
    const oldest = this.db
      .prepare("SELECT key, bytes FROM blobs ORDER BY seq ASC")
      .all() as Array<{ key: string; bytes: number }>;
    let removed = 0;
    for (const row of oldest) {
      if (total <= this.maxBytes) break;
      if (row.key === keep) continue;
      rmSync(this.path(row.key), { force: true });
      this.db.prepare("DELETE FROM blobs WHERE key = ?").run(row.key);
      total -= row.bytes;
      removed += 1;
    }
    return removed;
  }

  clear(): void {
    rmSync(join(this.dir, "blobs"), { recursive: true, force: true });
    mkdirSync(join(this.dir, "blobs"), { recursive: true });
    this.db.prepare("DELETE FROM blobs").run();
  }

  close(): void {
    this.db.close();
  }
}
```

- [ ] **Step 4: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS

- [ ] **Step 5: Verify nothing in `.cache/` is tracked**

Run: `git status --porcelain`
Expected: no `.cache/` paths listed.

- [ ] **Step 6: Commit**

```bash
git add lib/cache.ts test/cache.test.ts
git commit -m "Cache blobs locally, keyed by remote identity

Size and mtime are part of the key rather than checked after a lookup,
so a changed remote file misses instead of serving stale bytes. There
is no invalidation step and therefore no invalidation bug.

The index is not treated as the authority on what is on disk: a blob
deleted by hand reads as a miss, not a broken file handle."
```

---

### Task 10: Backend wiring — settings, RPC, and the byte routes

Replaces the scaffold's todo example with the real backend. This is where the pieces from Tasks 1–9 become a plugin.

**Files:**
- Rewrite: `server.ts`
- Create: `test/server.test.ts`
- Create: `lib/materialize.ts`
- Create: `test/materialize.test.ts`
- Rewrite: `app.tsx` (placeholder only — Task 11 builds the real UI)
- Delete: `skills/example-todos/`

**Interfaces:**
- Consumes: every `lib/` module from Tasks 1–9.
- Produces:
  - `export const rpcContract` with methods `status`, `setOverride`, `connect`, `list`, `preview`, `clearCache`
  - `export type Status`, `export type Entry`, `export type Preview` for `app.tsx`
  - HTTP route `GET /file` (a thumbnail is a different cache `variant` on the
    same route, not a second route)

- [ ] **Step 1: Write the failing tests**

Create `test/server.test.ts`:

```ts
import { ok, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";
import { createFakePluginHost } from "@get-bb/plugin-sdk/testing";
import plugin from "../server.ts";

async function host(settings: Record<string, unknown> = {}) {
  const made = createFakePluginHost({ pluginId: "remote-files", settings });
  await plugin(made.bb);
  return made.harness;
}

describe("status", () => {
  it("reports unset when nothing is configured", async () => {
    const harness = await host();
    const status = (await harness.behavior.callRpc("status", null)) as any;
    strictEqual(status.source, "unset");
    strictEqual(status.connected, false);
    // An unset plugin must explain itself rather than look broken.
    ok(status.hint.includes("REMOTE_FILES_SSH_TARGET"), status.hint);
  });

  it("reads the saved setting", async () => {
    const harness = await host({ sshTarget: "box", rootDir: "/srv" });
    const status = (await harness.behavior.callRpc("status", null)) as any;
    strictEqual(status.sshTarget, "box");
    strictEqual(status.source, "setting");
  });

  it("prefers a session override, and does not persist it", async () => {
    const harness = await host({ sshTarget: "box", rootDir: "/srv" });
    await harness.behavior.callRpc("setOverride", { sshTarget: "other", rootDir: "/tmp" });
    const status = (await harness.behavior.callRpc("status", null)) as any;
    strictEqual(status.sshTarget, "other");
    strictEqual(status.source, "override");
    const saved = (await harness.behavior.callRpc("status", null)) as any;
    strictEqual(saved.savedTarget, "box", "the saved setting must be untouched");
  });

  it("clears the override with a blank target", async () => {
    const harness = await host({ sshTarget: "box", rootDir: "/srv" });
    await harness.behavior.callRpc("setOverride", { sshTarget: "x", rootDir: "/x" });
    await harness.behavior.callRpc("setOverride", { sshTarget: "", rootDir: "" });
    strictEqual(((await harness.behavior.callRpc("status", null)) as any).source, "setting");
  });
});

describe("guards before connect", () => {
  it("refuses to list", async () => {
    const harness = await host();
    const result = (await harness.behavior.callRpc("list", { path: "." })) as any;
    strictEqual(result.ok, false);
  });

  it("reports an unusable target from connect rather than throwing", async () => {
    const harness = await host({ sshTarget: "-oProxyCommand=x", rootDir: "/srv" });
    const result = (await harness.behavior.callRpc("connect", null)) as any;
    strictEqual(result.connected, false);
    ok(String(result.error).length > 0);
  });
});

describe("connect", () => {
  // A reachable host whose start directory is wrong leaves capabilities
  // populated. Deriving "connected" from that reported success while `error`
  // held the failure, and `bb remote connect` printed "Connected." and exited
  // 0 while dropping the message.
  // These hold whichever way the connection failed, so they do not depend on
  // this machine being able to reach anything. The discriminating case — a
  // reachable host with an unusable root, where `capabilities` is populated
  // and the old expression still said "connected" — is proved one layer down,
  // in test/remote.test.ts.
  it("never reports connected alongside an error", async () => {
    const harness = await host({ sshTarget: "box", rootDir: "/srv" });
    const result = (await harness.behavior.callRpc("connect", null)) as any;
    ok(result.error !== null, "this environment cannot reach 'box'; the test needs a failure");
    strictEqual(result.connected, false, "connected must never be true alongside an error");
  });

  it("exits non-zero from the CLI when connect failed", async () => {
    const harness = await host({ sshTarget: "box", rootDir: "/srv" });
    const cli = await harness.behavior.runCli(["connect"]);
    strictEqual(cli.exitCode, 1, "a failed connect must not exit 0");
    ok(cli.stderr.length > 0, "a failed connect must say why");
  });
});

describe("byte routes", () => {
  it("refuses a request with no path", async () => {
    const harness = await host({ sshTarget: "box", rootDir: "/srv" });
    const response = await harness.behavior.fetchHttp("GET", "/file");
    strictEqual(response.status, 400);
  });

  it("refuses a well-formed key before connect", async () => {
    const harness = await host({ sshTarget: "box", rootDir: "/srv" });
    const response = await harness.behavior.fetchHttp("GET", `/file?key=${"a".repeat(64)}`);
    strictEqual(response.status, 409);
  });

  it("refuses a malformed key outright", async () => {
    const harness = await host({ sshTarget: "box", rootDir: "/srv" });
    const response = await harness.behavior.fetchHttp("GET", "/file?key=not-a-hash");
    strictEqual(response.status, 400);
  });
});

describe("cli", () => {
  it("prints usage with no arguments", async () => {
    const harness = await host();
    const result = await harness.behavior.runCli([]);
    strictEqual(result.exitCode, 0);
    ok(result.stdout.includes("bb remote"));
  });

  it("prints status as json", async () => {
    const harness = await host({ sshTarget: "box", rootDir: "/srv" });
    const result = await harness.behavior.runCli(["status", "--json"]);
    strictEqual(result.exitCode, 0);
    strictEqual(JSON.parse(result.stdout).sshTarget, "box");
  });

  it("sets the session override", async () => {
    const harness = await host({ sshTarget: "box", rootDir: "/srv" });
    await harness.behavior.runCli(["use", "other", "/tmp"]);
    strictEqual(((await harness.behavior.callRpc("status", null)) as any).sshTarget, "other");
  });

  it("fails with a message on an unknown verb", async () => {
    const harness = await host();
    const result = await harness.behavior.runCli(["frobnicate"]);
    strictEqual(result.exitCode, 1);
    ok(result.stderr.length > 0);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — the scaffold's `server.ts` has no `status` method.

- [ ] **Step 3: Delete the scaffold's example skill**

```bash
git rm -r skills/example-todos
```

- [ ] **Step 4: Rewrite `server.ts`**

```ts
// bb-plugin-remote-files — backend entry.
//
// Browses a remote filesystem over plain ssh. No mount, no SSHFS, and nothing
// written on the far side: the helper that produces listings and resizes
// images travels on ssh's stdin and exists only in that process's memory.
//
// The layering, bottom up: lib/ssh-argv + lib/ssh-run run one ssh call;
// lib/remote presents both host tiers as one interface; lib/policy decides
// what to fetch; lib/cache keeps the bytes here. This file is only wiring.
//
// Surfaces: an RPC contract for the panel, two HTTP routes that serve real
// image bytes to <img> tags, and a `bb remote` CLI giving agents the same
// reads.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { defineRpcContract, type BbPluginApi } from "@get-bb/plugin-sdk";
import { z } from "zod";
import { BlobCache } from "./lib/cache.ts";
import { materializeBlob } from "./lib/materialize.ts";
import { guessKind } from "./lib/policy.ts";
import { describeCapabilities } from "./lib/probe.ts";
import { RemoteClient, type Entry } from "./lib/remote.ts";
import { SHELL_TIER_CAVEAT } from "./lib/shell-tier.ts";
import { resolveConfig, type ResolvedConfig } from "./lib/target.ts";

export type { Entry };

const TARGET_ENV = "REMOTE_FILES_SSH_TARGET";
const ROOT_ENV = "REMOTE_FILES_ROOT_DIR";
/** Realtime channel the panel listens on when the connection state changes. */
const STATE_CHANGED = "connection-changed";

const entrySchema = z.object({
  name: z.string(),
  type: z.enum(["file", "dir", "link", "other"]),
  size: z.number(),
  mtime: z.number(),
  linkTarget: z.string().nullable(),
  linkType: z.string().nullable(),
  mode: z.number(),
});

const statusSchema = z.object({
  sshTarget: z.string(),
  rootDir: z.string(),
  source: z.enum(["override", "setting", "env", "unset"]),
  savedTarget: z.string(),
  savedRoot: z.string(),
  envTarget: z.string(),
  envRoot: z.string(),
  connected: z.boolean(),
  capabilities: z.string().nullable(),
  caveat: z.string().nullable(),
  error: z.string().nullable(),
  hint: z.string(),
  cacheBytes: z.number(),
});
export type Status = z.infer<typeof statusSchema>;

const previewSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("dir"), entries: z.array(entrySchema) }),
  z.object({
    kind: z.literal("text"),
    text: z.string(),
    truncated: z.boolean(),
    size: z.number(),
  }),
  z.object({
    kind: z.literal("image"),
    url: z.string(),
    size: z.number(),
    resized: z.boolean(),
  }),
  z.object({ kind: z.literal("none"), reason: z.string(), size: z.number() }),
  z.object({ kind: z.literal("error"), error: z.string() }),
]);
export type Preview = z.infer<typeof previewSchema>;

export const rpcContract = defineRpcContract({
  status: { input: z.null(), output: statusSchema },
  setOverride: {
    input: z.object({ sshTarget: z.string(), rootDir: z.string() }),
    output: statusSchema,
  },
  connect: { input: z.null(), output: statusSchema },
  list: {
    input: z.object({ path: z.string() }),
    output: z.discriminatedUnion("ok", [
      z.object({ ok: z.literal(true), path: z.string(), entries: z.array(entrySchema) }),
      z.object({ ok: z.literal(false), error: z.string() }),
    ]),
  },
  preview: { input: z.object({ path: z.string() }), output: previewSchema },
  clearCache: { input: z.null(), output: z.object({ cacheBytes: z.number() }) },
});

const HINT =
  `Set the host and start directory in this panel, with ` +
  `\`bb remote use <target> <dir>\`, in plugin settings, or with the ` +
  `${TARGET_ENV} and ${ROOT_ENV} environment variables of the bb server.`;

export default async function plugin(bb: BbPluginApi) {
  const settings = bb.settings.define({
    sshTarget: {
      type: "string",
      label: "SSH target",
      description: "user@host:port, host, or an ~/.ssh/config alias. Blank by default.",
      default: "",
    },
    rootDir: {
      type: "string",
      label: "Start directory",
      description: "Absolute path on the remote host. Browsing cannot escape it.",
      default: "",
    },
    cacheMaxMb: {
      type: "number",
      label: "Cache size limit (MB)",
      description: "Least-recently-used blobs are dropped past this.",
      default: 1024,
    },
  });
  const stored = await settings.get();

  // The cache lives in the plugin directory, beside this file, and is
  // gitignored. Deliberately not bb.storage.database(), which would put the
  // index in bb's data directory and split the cache across two places.
  const pluginDir = dirname(fileURLToPath(import.meta.url));
  const cache = new BlobCache(join(pluginDir, ".cache"), {
    maxBytes: Math.max(1, Number(stored.cacheMaxMb) || 1024) * 1024 * 1024,
  });

  /**
   * The session override: a plain variable, never persisted. Pointing the
   * plugin somewhere else for a minute leaves nothing behind.
   */
  let override: { sshTarget: string; rootDir: string } | null = null;
  let remote: RemoteClient | null = null;
  let lastError: string | null = null;
  /**
   * Whether the last connect actually succeeded — which is not the same as
   * knowing the host's tier. A reachable host with an unusable start
   * directory leaves capabilities populated, so deriving "connected" from
   * them reported success while `error` held the failure, and the CLI printed
   * "Connected." and exited 0 while dropping the message.
   */
  let connected = false;

  function effective(): ResolvedConfig {
    return resolveConfig({
      override,
      setting: { sshTarget: stored.sshTarget, rootDir: stored.rootDir },
      env: {
        sshTarget: process.env[TARGET_ENV] ?? "",
        rootDir: process.env[ROOT_ENV] ?? "",
      },
    });
  }

  function status(): Status {
    const config = effective();
    const capabilities = remote?.capabilities ?? null;
    return {
      sshTarget: config.sshTarget,
      rootDir: config.rootDir,
      source: config.source,
      savedTarget: stored.sshTarget,
      savedRoot: stored.rootDir,
      envTarget: process.env[TARGET_ENV] ?? "",
      envRoot: process.env[ROOT_ENV] ?? "",
      connected,
      capabilities: capabilities === null ? null : describeCapabilities(capabilities),
      caveat: capabilities?.tier === "shell" ? SHELL_TIER_CAVEAT : null,
      error: lastError,
      hint: HINT,
      cacheBytes: cache.totalBytes(),
    };
  }

  async function connect(): Promise<Status> {
    const config = effective();
    remote = null;
    lastError = null;
    connected = false;
    if (config.source === "unset") {
      lastError = "No SSH target is set.";
      bb.realtime.publish(STATE_CHANGED, {});
      return status();
    }
    const client = new RemoteClient({
      sshTarget: config.sshTarget,
      rootDir: config.rootDir,
    });
    const result = await client.connect();
    if (!result.ok) {
      lastError = result.error;
      // Keep the client only if it got far enough to know the host's tier, so
      // the panel can still explain what it found.
      remote = client.capabilities === null ? null : client;
      bb.realtime.publish(STATE_CHANGED, {});
      return status();
    }
    remote = client;
    connected = true;
    bb.log.info(`connected: ${describeCapabilities(result.capabilities)}`);
    bb.realtime.publish(STATE_CHANGED, {});
    return status();
  }

  /** Bound to this plugin's client and cache; the logic lives in lib/materialize.ts. */
  const materialize = (path: string, variant: "preview" | "raw") =>
    materializeBlob(
      { remote, cache, sshTarget: effective().sshTarget },
      path,
      variant,
    );

  bb.rpc.register(rpcContract, {
    status: async () => status(),
    setOverride: async ({ sshTarget, rootDir }) => {
      override = sshTarget.trim() === "" ? null : { sshTarget, rootDir };
      remote = null;
      connected = false;
      lastError = null;
      // An open panel is now looking at a connection that no longer exists.
      bb.realtime.publish(STATE_CHANGED, {});
      return status();
    },
    connect: async () => connect(),
    list: async ({ path }) => {
      if (remote === null || remote.capabilities === null) {
        return { ok: false as const, error: "Not connected." };
      }
      const result = await remote.list(path);
      if (!result.ok) return { ok: false as const, error: result.error };
      return { ok: true as const, path, entries: result.entries };
    },
    preview: async ({ path }) => {
      if (remote === null || remote.capabilities === null) {
        return { kind: "error" as const, error: "Not connected." };
      }
      const info = await remote.stat(path);
      if (!info.ok) return { kind: "error" as const, error: info.error };

      if (info.type === "dir") {
        const listed = await remote.list(path);
        return listed.ok
          ? { kind: "dir" as const, entries: listed.entries }
          : { kind: "error" as const, error: listed.error };
      }

      const name = path.slice(path.lastIndexOf("/") + 1);
      const kind = guessKind(name);
      const materialized = await materialize(path, "preview");
      if (!materialized.ok) {
        return { kind: "none" as const, reason: materialized.error, size: info.size };
      }
      if (kind === "image") {
        return {
          kind: "image" as const,
          // A URL, not bytes: the browser fetches this from the HTTP route
          // below and caches it by ETag.
          url: `/api/v1/plugins/${bb.pluginId}/http/file?key=${materialized.key}`,
          size: info.size,
          resized: materialized.resized,
        };
      }
      if (kind === "text") {
        const hit = cache.get(materialized.key);
        if (hit === null) return { kind: "error" as const, error: "The cached copy vanished." };
        return {
          kind: "text" as const,
          text: readFileSync(hit.path, "utf8"),
          truncated: materialized.truncated,
          size: info.size,
        };
      }
      return {
        kind: "none" as const,
        reason: "Not something this browser can preview.",
        size: info.size,
      };
    },
    clearCache: async () => {
      cache.clear();
      return { cacheBytes: cache.totalBytes() };
    },
  });

  // Bytes for <img>. The key is opaque and already refers to a blob this
  // plugin fetched and confined, so the route reads the cache and nothing
  // else — it never takes a remote path from the browser.
  bb.http.route("GET", "/file", async (context) => {
    const key = new URL(context.req.url).searchParams.get("key");
    if (key === null || !/^[0-9a-f]{64}$/.test(key)) {
      return new Response("A blob key is required", { status: 400 });
    }
    if (remote === null) return new Response("Not connected", { status: 409 });
    const hit = cache.get(key);
    if (hit === null) return new Response("Not cached", { status: 404 });
    return new Response(readFileSync(hit.path), {
      headers: {
        "content-type": hit.mime ?? "application/octet-stream",
        "content-length": String(hit.bytes),
        // The key already encodes size and mtime, so a hit can never be stale.
        etag: `"${key}"`,
        "cache-control": "private, max-age=31536000, immutable",
      },
    });
  });

  const usage = [
    "Usage:",
    "  bb remote status [--json]",
    "  bb remote use <target> [start-dir]",
    "  bb remote connect [--json]",
    "  bb remote ls [path] [--json]",
    "  bb remote cat <path>",
  ].join("\n");

  bb.cli.register({
    name: "remote",
    summary: "Browse a remote filesystem over ssh",
    commands: [
      { name: "status", summary: "Show the target, tier, and cache size", usage: "bb remote status [--json]" },
      { name: "use", summary: "Set the session target and start directory", usage: "bb remote use <target> [start-dir]" },
      { name: "connect", summary: "Connect and probe the host", usage: "bb remote connect [--json]" },
      { name: "ls", summary: "List a directory", usage: "bb remote ls [path] [--json]" },
      { name: "cat", summary: "Print a text file's head", usage: "bb remote cat <path>" },
    ],
    async run(argv) {
      const json = argv.includes("--json");
      const [command, ...args] = argv.filter((arg) => arg !== "--json");
      const reply = (value: unknown, text: string) => ({
        exitCode: 0,
        stdout: json ? JSON.stringify(value, null, 2) : text,
      });
      switch (command) {
        case undefined:
        case "help":
        case "--help":
          return { exitCode: 0, stdout: usage };
        case "status": {
          const current = status();
          return reply(
            current,
            [
              `target:  ${current.sshTarget || "(unset)"} (${current.source})`,
              `root:    ${current.rootDir || "(unset)"}`,
              `state:   ${current.connected ? current.capabilities : "not connected"}`,
              `cache:   ${(current.cacheBytes / 1024 / 1024).toFixed(1)} MB`,
              ...(current.error === null ? [] : [`error:   ${current.error}`]),
            ].join("\n"),
          );
        }
        case "use": {
          if (args[0] === undefined) break;
          override = { sshTarget: args[0], rootDir: args[1] ?? "" };
          remote = null;
          connected = false;
          lastError = null;
          bb.realtime.publish(STATE_CHANGED, {});
          return reply(status(), `Using ${args[0]} at ${args[1] ?? "(unset)"} for this session.`);
        }
        case "connect": {
          const result = await connect();
          if (!result.connected) return { exitCode: 1, stderr: result.error ?? "Could not connect." };
          return reply(result, `Connected. ${result.capabilities}`);
        }
        case "ls": {
          if (remote === null) return { exitCode: 1, stderr: `Not connected. Run "bb remote connect".` };
          const result = await remote.list(args[0] ?? ".");
          if (!result.ok) return { exitCode: 1, stderr: result.error };
          return reply(
            result.entries,
            result.entries
              .map((entry) => `${entry.type === "dir" ? "d" : "-"} ${String(entry.size).padStart(10)}  ${entry.name}`)
              .join("\n"),
          );
        }
        case "cat": {
          if (args[0] === undefined) break;
          if (remote === null) return { exitCode: 1, stderr: `Not connected. Run "bb remote connect".` };
          const materialized = await materialize(args[0], "preview");
          if (!materialized.ok) return { exitCode: 1, stderr: materialized.error };
          const hit = cache.get(materialized.key);
          if (hit === null) return { exitCode: 1, stderr: "The cached copy vanished." };
          return { exitCode: 0, stdout: readFileSync(hit.path, "utf8") };
        }
      }
      return { exitCode: 1, stderr: usage };
    },
  });

  bb.onDispose(() => {
    cache.close();
  });
}
```

- [ ] **Step 4a: Create `lib/materialize.ts`**

Fetching per the size policy and caching the result is the one piece of
`server.ts` that needs nothing from `bb`. Out here it can be tested against a
duck-typed remote, which is what makes the hit/miss parity invariant provable
rather than merely inspected.

```ts
// Fetch a path per the size policy and cache the bytes, returning the key.
//
// Lives outside server.ts because it closes over nothing from the plugin API
// — only a remote, a cache, and the target string. That also makes its one
// subtle guarantee testable: `truncated` and `resized` describe the PLAN, so
// a cache hit says exactly what a cache miss said. Reading them off the fetch
// result made a cached 2GB log lose its "showing the first part" notice.
import { BlobCache, cacheKey } from "./cache.ts";
import { guessKind, planFetch } from "./policy.ts";
import type { Capabilities } from "./probe.ts";

/** Only the parts of RemoteClient this needs, so a test can stand one in. */
export type MaterializeRemote = {
  capabilities: Capabilities | null;
  stat(rel: string): Promise<
    { ok: true; realpath: string; type: string; size: number; mtime: number }
    | { ok: false; error: string }
  >;
  fetch(
    rel: string,
    opts: { limit?: number; resizeTo?: number },
  ): Promise<
    { ok: true; bytes: Buffer; truncated: boolean; resized: boolean; mime: string | null }
    | { ok: false; error: string }
  >;
};

export type Materialized =
  | { ok: true; key: string; mime: string | null; truncated: boolean; resized: boolean; size: number }
  | { ok: false; error: string };

export async function materializeBlob(
  deps: { remote: MaterializeRemote | null; cache: BlobCache; sshTarget: string },
  path: string,
  variant: "preview" | "raw",
): Promise<Materialized> {
  const { remote, cache, sshTarget } = deps;
  if (remote === null || remote.capabilities === null) {
    return { ok: false, error: "Not connected." };
  }
  const info = await remote.stat(path);
  if (!info.ok) return info;

  const name = path.slice(path.lastIndexOf("/") + 1);
  const action = planFetch({
    name,
    size: info.size,
    type: info.type,
    capabilities: remote.capabilities,
  });
  if (action.kind === "refuse") return { ok: false, error: action.reason };

  // Both flags come from the plan, which is computed before the cache is
  // consulted and is therefore identical on a hit and a miss.
  const truncated = action.kind === "head";
  const resized = action.kind === "resize";

  const key = cacheKey({
    sshTarget,
    realpath: info.realpath,
    size: info.size,
    mtime: info.mtime,
    variant: `${variant}:${action.kind}`,
  });

  const hit = cache.get(key);
  if (hit !== null) {
    return { ok: true, key, mime: hit.mime, truncated, resized, size: info.size };
  }

  const fetched = await remote.fetch(path, {
    limit: action.kind === "head" ? action.limit : undefined,
    resizeTo: action.kind === "resize" ? action.maxDim : undefined,
  });
  if (!fetched.ok) return fetched;

  const mime =
    fetched.mime ??
    (guessKind(name) === "image"
      ? `image/${name.split(".").pop()?.toLowerCase()}`
      : null);
  cache.put(key, fetched.bytes, { mime, remotePath: info.realpath });
  return { ok: true, key, mime, truncated, resized, size: info.size };
}
```

Create `test/materialize.test.ts`:

```ts
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ok, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";
import { BlobCache } from "../lib/cache.ts";
import { materializeBlob, type MaterializeRemote } from "../lib/materialize.ts";
import type { Capabilities } from "../lib/probe.ts";

const caps: Capabilities = {
  tier: "python", python3: true, pil: true, magick: null, vips: false,
  statFlavor: "gnu", uname: "Linux", resize: "pil",
};

/** Counts its own calls, so a cache hit is distinguishable from a miss. */
function fakeRemote(size: number, name = "big.log"): MaterializeRemote & { fetches: number } {
  return {
    capabilities: caps,
    fetches: 0,
    async stat() {
      return { ok: true, realpath: `/srv/${name}`, type: "file", size, mtime: 7 };
    },
    async fetch(this: { fetches: number }) {
      this.fetches += 1;
      return {
        ok: true, bytes: Buffer.alloc(64), truncated: true, resized: false, mime: null,
      };
    },
  };
}

const cacheIn = () => new BlobCache(mkdtempSync(join(tmpdir(), "rf-mat-")));

describe("materializeBlob", () => {
  it("reports a truncated read the same way on a hit as on a miss", async () => {
    const remote = fakeRemote(5_000_000);
    const cache = cacheIn();
    const miss = await materializeBlob({ remote, cache, sshTarget: "box" }, "big.log", "preview");
    const hit = await materializeBlob({ remote, cache, sshTarget: "box" }, "big.log", "preview");

    strictEqual(remote.fetches, 1, "the second call must be served from cache");
    ok(miss.ok && hit.ok);
    if (miss.ok && hit.ok) {
      strictEqual(miss.truncated, true);
      strictEqual(hit.truncated, true, "a cache hit lost the truncation notice");
      strictEqual(hit.key, miss.key);
      strictEqual(hit.size, miss.size);
    }
    cache.close();
  });

  it("reports a resize the same way on a hit as on a miss", async () => {
    const remote = fakeRemote(5_000_000, "photo.jpg");
    const cache = cacheIn();
    const miss = await materializeBlob({ remote, cache, sshTarget: "box" }, "photo.jpg", "preview");
    const hit = await materializeBlob({ remote, cache, sshTarget: "box" }, "photo.jpg", "preview");
    ok(miss.ok && hit.ok);
    if (miss.ok && hit.ok) {
      strictEqual(miss.resized, true);
      strictEqual(hit.resized, true, "a cache hit lost the downscaling notice");
    }
    cache.close();
  });

  it("refuses before connect", async () => {
    const result = await materializeBlob(
      { remote: null, cache: cacheIn(), sshTarget: "box" }, "a.txt", "preview",
    );
    strictEqual(result.ok, false);
  });

  it("keeps a head and a whole read of one file in different cache slots", async () => {
    const cache = cacheIn();
    const big = await materializeBlob(
      { remote: fakeRemote(5_000_000), cache, sshTarget: "box" }, "big.log", "preview",
    );
    const small = await materializeBlob(
      { remote: fakeRemote(10, "big.log"), cache, sshTarget: "box" }, "big.log", "preview",
    );
    ok(big.ok && small.ok);
    if (big.ok && small.ok) ok(big.key !== small.key, "head and whole collided");
    cache.close();
  });
});
```

- [ ] **Step 4b: Replace `app.tsx` with a placeholder**

The scaffold's `app.tsx` calls the todo contract this task just deleted, so the
tree cannot typecheck until it goes. Task 11 builds the real browser on top of
this; it exists so that the gate between the two tasks still means something.

```tsx
// bb-plugin-remote-files — frontend entry.
//
// A placeholder. Task 11 replaces it with the Miller-column browser; this
// exists so the tree typechecks between the backend landing and the UI
// arriving, rather than leaving a red tree for the next task to inherit and
// mistake for its own.
import { useEffect, useState } from "react";
import { definePluginApp, useRpc } from "@get-bb/plugin-sdk/app";
import type { Status, rpcContract } from "./server";

export default definePluginApp(() => {
  const rpc = useRpc<typeof rpcContract>();
  const [status, setStatus] = useState<Status | null>(null);

  useEffect(() => {
    void rpc.call("status", null).then(setStatus);
  }, [rpc]);

  if (status === null) {
    return <div className="p-4 text-sm text-muted-foreground">Loading…</div>;
  }
  return (
    <div className="p-4 text-sm text-muted-foreground">
      {status.source === "unset"
        ? status.hint
        : `${status.sshTarget} — ${status.connected ? status.capabilities : "not connected"}`}
    </div>
  );
});
```

- [ ] **Step 5: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS

- [ ] **Step 6: Commit**

```bash
git add server.ts app.tsx lib/materialize.ts test/materialize.test.ts test/server.test.ts
git commit -m "Wire the backend: settings, RPC, byte routes, and bb remote

Replaces the scaffold's todo example. Config resolves through the four
tiers, with the session override held in a plain variable so pointing
the plugin at another host for a minute persists nothing.

The /file route takes an opaque blob key, never a remote path from the
browser: the confinement check already happened when the bytes were
fetched, and the route only reads what this plugin put in the cache."
```

---

### Task 11: The panel — Miller columns and keyboard navigation

**Files:**
- Rewrite: `app.tsx` (currently a placeholder left by Task 10)
- Create: `lib/columns.ts`
- Create: `test/columns.test.ts`

**Interfaces:**
- Consumes: `Entry`, `Status`, `Preview`, `rpcContract` from `server.ts`.
- Produces:
  - `type Column = { path: string; entries: Entry[]; selected: number }`
  - `pathOf(segments: string[]): string`
  - `columnsFor(segments: string[]): string[]`
  - `moveSelection(column: Column, delta: number | "start" | "end"): number`
  - `filterEntries(entries: Entry[], query: string): Entry[]`
  - `shouldHandleKey(event: { metaKey; ctrlKey; altKey }, target: { tagName?; isContentEditable? } | null): boolean`

- [ ] **Step 1: Write the failing tests**

Create `test/columns.test.ts`. The navigation arithmetic is where off-by-ones live, so it is tested apart from React.

```ts
import { deepStrictEqual, strictEqual } from "node:assert/strict";
import { describe, it } from "node:test";
import {
  columnsFor,
  filterEntries,
  moveSelection,
  pathOf,
  shouldHandleKey,
} from "../lib/columns.ts";
import type { Entry } from "../lib/shell-tier.ts";

const entry = (name: string, type: Entry["type"] = "file"): Entry => ({
  name, type, size: 0, mtime: 0, linkTarget: null, linkType: null, mode: 0,
});

describe("pathOf", () => {
  it("renders the root as a dot", () => {
    strictEqual(pathOf([]), ".");
  });

  it("joins segments", () => {
    strictEqual(pathOf(["a", "b"]), "a/b");
  });

  it("does not mangle a segment with a space", () => {
    strictEqual(pathOf(["my dir", "b"]), "my dir/b");
  });
});

describe("columnsFor", () => {
  it("always shows the root", () => {
    deepStrictEqual(columnsFor([]), ["."]);
  });

  it("shows every ancestor plus the current directory", () => {
    deepStrictEqual(columnsFor(["a", "b"]), [".", "a", "a/b"]);
  });
});

describe("moveSelection", () => {
  const column = { path: ".", entries: [entry("a"), entry("b"), entry("c")], selected: 1 };

  it("moves by delta", () => {
    strictEqual(moveSelection(column, 1), 2);
    strictEqual(moveSelection(column, -1), 0);
  });

  // Clamping rather than wrapping: in a file manager, holding j past the end
  // should rest on the last row, not silently return to the top.
  it("clamps at both ends", () => {
    strictEqual(moveSelection(column, 99), 2);
    strictEqual(moveSelection(column, -99), 0);
  });

  it("jumps to the ends", () => {
    strictEqual(moveSelection(column, "start"), 0);
    strictEqual(moveSelection(column, "end"), 2);
  });

  it("stays at zero in an empty column", () => {
    strictEqual(moveSelection({ path: ".", entries: [], selected: 0 }, 1), 0);
    strictEqual(moveSelection({ path: ".", entries: [], selected: 0 }, "end"), 0);
  });
});

describe("shouldHandleKey", () => {
  const asInput = (tagName: string) => ({ tagName, isContentEditable: false });

  it("declines a key typed into a text field", () => {
    strictEqual(shouldHandleKey({ metaKey: false, ctrlKey: false, altKey: false }, asInput("INPUT")), false);
    strictEqual(shouldHandleKey({ metaKey: false, ctrlKey: false, altKey: false }, asInput("TEXTAREA")), false);
    strictEqual(
      shouldHandleKey({ metaKey: false, ctrlKey: false, altKey: false }, { tagName: "DIV", isContentEditable: true }),
      false,
    );
  });

  it("declines a modified key so the host keeps its shortcuts", () => {
    for (const modifier of ["metaKey", "ctrlKey", "altKey"] as const) {
      strictEqual(
        shouldHandleKey({ metaKey: false, ctrlKey: false, altKey: false, [modifier]: true }, asInput("DIV")),
        false,
        modifier,
      );
    }
  });

  it("handles an unmodified key outside a text field", () => {
    strictEqual(shouldHandleKey({ metaKey: false, ctrlKey: false, altKey: false }, asInput("DIV")), true);
  });

  it("handles a key when there is no target at all", () => {
    strictEqual(shouldHandleKey({ metaKey: false, ctrlKey: false, altKey: false }, null), true);
  });
});

describe("filterEntries", () => {
  const entries = [entry("Alpha"), entry("beta"), entry("gamma-beta")];

  it("returns everything for a blank query", () => {
    strictEqual(filterEntries(entries, "  ").length, 3);
  });

  it("matches case-insensitively anywhere in the name", () => {
    deepStrictEqual(filterEntries(entries, "BET").map((e) => e.name), ["beta", "gamma-beta"]);
  });

  it("returns nothing when nothing matches", () => {
    strictEqual(filterEntries(entries, "zzz").length, 0);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: FAIL — `Cannot find module '../lib/columns.ts'`

- [ ] **Step 3: Implement `lib/columns.ts`**

```ts
// Navigation arithmetic for the column strip. Pure and free of React, because
// this is where the off-by-ones live and they are cheaper to catch here.
import type { Entry } from "./shell-tier.ts";

export type Column = { path: string; entries: Entry[]; selected: number };

/** Path segments to the relative path the backend takes. */
export function pathOf(segments: string[]): string {
  return segments.length === 0 ? "." : segments.join("/");
}

/** The strip: the root, every ancestor, and the directory currently open. */
export function columnsFor(segments: string[]): string[] {
  const paths = ["."];
  for (let index = 0; index < segments.length; index += 1) {
    paths.push(segments.slice(0, index + 1).join("/"));
  }
  return paths;
}

/**
 * Clamped, never wrapped. Holding j past the last row should rest there; a
 * file manager that jumps back to the top loses the user's place.
 */
export function moveSelection(column: Column, delta: number | "start" | "end"): number {
  const last = Math.max(0, column.entries.length - 1);
  if (delta === "start") return 0;
  if (delta === "end") return last;
  return Math.min(last, Math.max(0, column.selected + delta));
}

/**
 * Whether a keystroke is ours to act on.
 *
 * Two things it protects: a modified key belongs to the host's shortcuts, and
 * a key typed into a text field belongs to that field — without the second,
 * typing "github.com" into the SSH target box navigates the browser instead
 * of inserting text.
 */
export function shouldHandleKey(
  event: { metaKey: boolean; ctrlKey: boolean; altKey: boolean },
  target: { tagName?: string; isContentEditable?: boolean } | null,
): boolean {
  if (event.metaKey || event.ctrlKey || event.altKey) return false;
  if (target?.isContentEditable === true) return false;
  return target?.tagName !== "INPUT" && target?.tagName !== "TEXTAREA";
}

export function filterEntries(entries: Entry[], query: string): Entry[] {
  const needle = query.trim().toLowerCase();
  if (needle === "") return entries;
  return entries.filter((entry) => entry.name.toLowerCase().includes(needle));
}
```

- [ ] **Step 4: Rewrite `app.tsx`**

```tsx
// bb-plugin-remote-files — frontend entry.
//
// A remote file browser laid out like ranger and yazi: a horizontally
// scrolling strip of directory columns, the selection previewed in the pane on
// the right. Images come from the plugin's HTTP route as real bytes.
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { definePluginApp, useRealtime, useRpc } from "@get-bb/plugin-sdk/app";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import {
  columnsFor,
  filterEntries,
  moveSelection,
  pathOf,
  shouldHandleKey,
} from "@/lib/columns";
import type { Entry } from "@/lib/shell-tier";
import type { Preview, Status, rpcContract } from "./server";

type Rpc = ReturnType<typeof useRpc<typeof rpcContract>>;

type ColumnState =
  | { state: "loading" }
  | { state: "ready"; entries: Entry[] }
  | { state: "failed"; error: string };

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`;
}

/** The connection bar: target, start directory, Test, and Connect. */
function ConnectionBar({
  status,
  rpc,
  onChanged,
}: {
  status: Status | null;
  rpc: Rpc;
  onChanged: () => void;
}) {
  const [target, setTarget] = useState("");
  const [root, setRoot] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (status === null) return;
    setTarget(status.sshTarget);
    setRoot(status.rootDir);
  }, [status?.sshTarget, status?.rootDir]);

  const apply = useCallback(
    async (connect: boolean) => {
      setBusy(true);
      try {
        await rpc.call("setOverride", { sshTarget: target, rootDir: root });
        if (connect) await rpc.call("connect", null);
      } finally {
        setBusy(false);
        onChanged();
      }
    },
    [rpc, target, root, onChanged],
  );

  return (
    <div className="flex flex-col gap-2 border-b px-3 py-2">
      <div className="flex flex-wrap items-center gap-2">
        <Input
          className="w-64"
          placeholder="user@host:port or ~/.ssh/config alias"
          value={target}
          onChange={(event) => setTarget(event.target.value)}
        />
        <Input
          className="w-64"
          placeholder="/absolute/start/directory"
          value={root}
          onChange={(event) => setRoot(event.target.value)}
        />
        <Button size="sm" variant="secondary" disabled={busy} onClick={() => apply(false)}>
          Test
        </Button>
        <Button size="sm" disabled={busy} onClick={() => apply(true)}>
          Connect
        </Button>
        {status !== null && (
          <span className="text-xs text-muted-foreground">
            {status.source === "unset" ? "not configured" : `from ${status.source}`}
          </span>
        )}
      </div>
      {status?.error != null && (
        <pre className="whitespace-pre-wrap text-xs text-destructive">{status.error}</pre>
      )}
      {status?.connected === true && (
        <div className="text-xs text-muted-foreground">{status.capabilities}</div>
      )}
      {status?.caveat != null && (
        <div className="text-xs text-amber-600 dark:text-amber-400">{status.caveat}</div>
      )}
      {status?.source === "unset" && (
        <div className="text-xs text-muted-foreground">{status.hint}</div>
      )}
    </div>
  );
}

function EntryRow({
  entry,
  active,
  focused,
  onSelect,
  onOpen,
}: {
  entry: Entry;
  active: boolean;
  focused: boolean;
  onSelect: () => void;
  onOpen: () => void;
}) {
  const isDir = entry.type === "dir" || entry.linkType === "dir";
  return (
    <button
      type="button"
      onClick={onSelect}
      onDoubleClick={onOpen}
      className={cn(
        "flex w-full items-baseline gap-2 px-2 py-1 text-left text-sm",
        active && (focused ? "bg-primary text-primary-foreground" : "bg-muted"),
      )}
    >
      <span className="w-3 shrink-0 opacity-60">{isDir ? "/" : entry.type === "link" ? "@" : ""}</span>
      <span className="truncate">{entry.name}</span>
      <span className="ml-auto shrink-0 text-xs opacity-60">
        {isDir ? "" : formatSize(entry.size)}
      </span>
    </button>
  );
}

export default definePluginApp(() => {
  const rpc = useRpc<typeof rpcContract>();
  const [status, setStatus] = useState<Status | null>(null);
  const [segments, setSegments] = useState<string[]>([]);
  // A failed listing must not render as an empty directory: a permission
  // error and an empty folder look identical otherwise, with no way to retry.
  const [listings, setListings] = useState<Record<string, ColumnState>>({});
  const [selection, setSelection] = useState<Record<string, number>>({});
  const [filter, setFilter] = useState("");
  const [filtering, setFiltering] = useState(false);
  const [preview, setPreview] = useState<Preview | null>(null);
  const stripRef = useRef<HTMLDivElement>(null);

  const refreshStatus = useCallback(() => {
    void rpc.call("status", null).then(setStatus);
  }, [rpc]);

  useEffect(refreshStatus, [refreshStatus]);
  useRealtime("connection-changed", refreshStatus);

  const paths = useMemo(() => columnsFor(segments), [segments]);
  const currentPath = pathOf(segments);
  const currentColumn = listings[currentPath];
  const entries = useMemo(
    () =>
      filterEntries(currentColumn?.state === "ready" ? currentColumn.entries : [], filter),
    [currentColumn, filter],
  );
  const selected = Math.min(selection[currentPath] ?? 0, Math.max(0, entries.length - 1));
  const selectedEntry = entries[selected] ?? null;

  // Load every column in the strip. Cheap: the backend caches nothing here,
  // but ControlMaster makes each call a few milliseconds.
  useEffect(() => {
    if (status?.connected !== true) return;
    for (const path of paths) {
      if (listings[path] !== undefined) continue;
      // Marked loading first, so this effect's next run skips the path rather
      // than issuing a second request for it.
      setListings((prior) =>
        prior[path] === undefined ? { ...prior, [path]: { state: "loading" } } : prior,
      );
      void rpc
        .call("list", { path })
        .then((result) => {
          setListings((prior) => ({
            ...prior,
            [path]: result.ok
              ? { state: "ready", entries: result.entries }
              : { state: "failed", error: result.error },
          }));
        })
        .catch((cause: unknown) => {
          setListings((prior) => ({
            ...prior,
            [path]: {
              state: "failed",
              error: cause instanceof Error ? cause.message : String(cause),
            },
          }));
        });
    }
  }, [paths, status?.connected, rpc, listings]);

  // Reset everything when the connection changes underneath us.
  //
  // Declared after the loading effect on purpose. On the render where status
  // first resolves, both fire; this one wipes the cache the other just began
  // filling, which costs one duplicate list of the root and nothing else.
  // Reversed, it would wipe a listing that had already committed.
  useEffect(() => {
    setListings({});
    setSelection({});
    setSegments([]);
    setPreview(null);
  }, [status?.sshTarget, status?.rootDir, status?.connected]);

  useEffect(() => {
    if (selectedEntry === null || status?.connected !== true) {
      setPreview(null);
      return;
    }
    const path = pathOf([...segments, selectedEntry.name]);
    let stale = false;
    void rpc.call("preview", { path }).then((result) => {
      if (!stale) setPreview(result);
    });
    return () => {
      stale = true;
    };
    // currentPath is deliberately absent: it is derived from segments, which
    // is already listed, and naming it twice implies a distinction there
    // isn't one.
  }, [selectedEntry?.name, status?.connected, rpc, segments]);

  const descend = useCallback(() => {
    if (selectedEntry === null) return;
    if (selectedEntry.type !== "dir" && selectedEntry.linkType !== "dir") return;
    setSegments((prior) => [...prior, selectedEntry.name]);
    setFilter("");
  }, [selectedEntry]);

  const ascend = useCallback(() => {
    setSegments((prior) => prior.slice(0, -1));
    setFilter("");
  }, []);

  useEffect(() => {
    stripRef.current?.scrollTo({ left: stripRef.current.scrollWidth, behavior: "smooth" });
  }, [segments.length]);

  const onKeyDown = useCallback(
    (event: React.KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (!shouldHandleKey(event, target)) {
        // Escape still leaves the filter box, which is itself a text field.
        if (event.key === "Escape") {
          setFiltering(false);
          setFilter("");
          target?.blur();
        }
        return;
      }

      const column = { path: currentPath, entries, selected };
      const set = (next: number) =>
        setSelection((prior) => ({ ...prior, [currentPath]: next }));
      switch (event.key) {
        case "j":
        case "ArrowDown": set(moveSelection(column, 1)); break;
        case "k":
        case "ArrowUp": set(moveSelection(column, -1)); break;
        case "l":
        case "ArrowRight":
        case "Enter": descend(); break;
        case "h":
        case "ArrowLeft": ascend(); break;
        case "G": set(moveSelection(column, "end")); break;
        case "g": set(moveSelection(column, "start")); break;
        case "/": setFiltering(true); break;
        // Handled only to swallow it: the panel's container is focusable, and
        // an unhandled space scrolls the page out from under the columns.
        case " ": break;
        default: return;
      }
      event.preventDefault();
    },
    [currentPath, entries, selected, descend, ascend],
  );

  return (
    <div className="flex h-full flex-col outline-none" tabIndex={0} onKeyDown={onKeyDown}>
      <ConnectionBar status={status} rpc={rpc} onChanged={refreshStatus} />

      {status?.connected !== true ? (
        <div className="flex flex-1 items-center justify-center p-8 text-sm text-muted-foreground">
          {status?.source === "unset"
            ? "Set a host and a start directory to begin."
            : "Not connected."}
        </div>
      ) : (
        <>
          <div className="flex items-center gap-2 border-b px-3 py-1 text-xs">
            <span className="text-muted-foreground">{status.rootDir}</span>
            {segments.map((segment) => (
              <span key={segment}>/ {segment}</span>
            ))}
            {filtering && (
              <Input
                autoFocus
                className="ml-auto h-6 w-48"
                placeholder="filter"
                value={filter}
                onChange={(event) => setFilter(event.target.value)}
                onBlur={() => setFiltering(false)}
              />
            )}
          </div>

          <div className="flex min-h-0 flex-1">
            <div ref={stripRef} className="flex min-w-0 flex-1 overflow-x-auto">
              {paths.map((path, index) => {
                const isCurrent = index === paths.length - 1;
                const loaded = listings[path];
                const columnEntries = isCurrent
                  ? entries
                  : loaded?.state === "ready"
                    ? loaded.entries
                    : [];
                const activeName = isCurrent
                  ? selectedEntry?.name
                  : segments[index];
                return (
                  <div key={path} className="w-56 shrink-0 overflow-y-auto border-r">
                    {loaded === undefined || loaded.state === "loading" ? (
                      <div className="p-2 text-xs text-muted-foreground">loading…</div>
                    ) : loaded.state === "failed" ? (
                      <div className="p-2 text-xs text-destructive">{loaded.error}</div>
                    ) : columnEntries.length === 0 ? (
                      <div className="p-2 text-xs text-muted-foreground">empty</div>
                    ) : (
                      columnEntries.map((entry, row) => (
                        <EntryRow
                          key={entry.name}
                          entry={entry}
                          active={entry.name === activeName}
                          focused={isCurrent}
                          onSelect={() => {
                            if (isCurrent) {
                              setSelection((prior) => ({ ...prior, [path]: row }));
                              return;
                            }
                            // An ancestor column. Clicking a directory walks
                            // into it — that is the whole Miller-column
                            // gesture. Ignoring the clicked row and merely
                            // truncating to the column's own path, as an
                            // earlier version did, made it impossible to
                            // click across into another branch.
                            const base = path === "." ? [] : path.split("/");
                            const isDir =
                              entry.type === "dir" || entry.linkType === "dir";
                            setSegments(isDir ? [...base, entry.name] : base);
                            setSelection((prior) => ({ ...prior, [path]: row }));
                            setFilter("");
                          }}
                          onOpen={() => {
                            if (!isCurrent) return;
                            setSelection((prior) => ({ ...prior, [path]: row }));
                            if (entry.type === "dir" || entry.linkType === "dir") {
                              setSegments((prior) => [...prior, entry.name]);
                            }
                          }}
                        />
                      ))
                    )}
                  </div>
                );
              })}
            </div>
            <PreviewPane preview={preview} entry={selectedEntry} />
          </div>
        </>
      )}
    </div>
  );
});

/** Defined in Task 12. */
function PreviewPane(_props: { preview: Preview | null; entry: Entry | null }) {
  return null;
}
```

- [ ] **Step 5: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS

- [ ] **Step 6: Commit**

```bash
git add app.tsx lib/columns.ts test/columns.test.ts
git commit -m "Add the column strip and its keyboard navigation

The navigation arithmetic is a pure module tested apart from React,
because that is where the off-by-ones live.

Selection clamps rather than wraps: holding j past the last row should
rest there, and a file manager that jumps back to the top loses the
user's place."
```

---

### Task 12: The preview pane

**Files:**
- Modify: `app.tsx` (replace the `PreviewPane` stub at the end of the file)

**Interfaces:**
- Consumes: `Preview` from `server.ts`, `Entry` from `lib/shell-tier.ts`, `formatSize` already defined in `app.tsx`.
- Produces: the real `PreviewPane` component.

- [ ] **Step 1: Replace the stub**

Delete the stub at the bottom of `app.tsx`:

```tsx
/** Defined in Task 12. */
function PreviewPane(_props: { preview: Preview | null; entry: Entry | null }) {
  return null;
}
```

and put this in its place:

```tsx
/**
 * The right-hand pane. Every branch of Preview is rendered, including the
 * ones that are not content: "too large" and "cannot preview" are states worth
 * showing, not blanks to leave the user staring at.
 */
function PreviewPane({
  preview,
  entry,
}: {
  preview: Preview | null;
  entry: Entry | null;
}) {
  return (
    <div className="flex w-[28rem] shrink-0 flex-col border-l">
      {entry !== null && (
        <div className="truncate border-b px-3 py-1 text-xs text-muted-foreground">
          {entry.name}
          {entry.type !== "dir" && ` — ${formatSize(entry.size)}`}
          {entry.linkTarget !== null && ` → ${entry.linkTarget}`}
        </div>
      )}

      <div className="min-h-0 flex-1 overflow-auto">
        {preview === null ? (
          <div className="p-4 text-sm text-muted-foreground">
            {entry === null ? "Nothing selected." : "Loading…"}
          </div>
        ) : preview.kind === "dir" ? (
          // One level ahead of the selection, as in ranger and yazi.
          <div className="py-1">
            {preview.entries.length === 0 ? (
              <div className="px-3 py-2 text-sm text-muted-foreground">empty directory</div>
            ) : (
              preview.entries.map((child) => (
                <div key={child.name} className="flex items-baseline gap-2 px-3 py-0.5 text-sm">
                  <span className="w-3 shrink-0 opacity-60">
                    {child.type === "dir" ? "/" : child.type === "link" ? "@" : ""}
                  </span>
                  <span className="truncate">{child.name}</span>
                  <span className="ml-auto shrink-0 text-xs opacity-60">
                    {child.type === "dir" ? "" : formatSize(child.size)}
                  </span>
                </div>
              ))
            )}
          </div>
        ) : preview.kind === "image" ? (
          <div className="flex h-full flex-col">
            {/* Real bytes from the plugin's HTTP route, cached by ETag. */}
            <img
              src={preview.url}
              alt=""
              className="max-h-full max-w-full self-center object-contain p-2"
            />
            {preview.resized && (
              <div className="px-3 pb-2 text-xs text-muted-foreground">
                Downscaled for preview — the original is {formatSize(preview.size)}.
              </div>
            )}
          </div>
        ) : preview.kind === "text" ? (
          <div>
            <pre className="whitespace-pre-wrap px-3 py-2 font-mono text-xs leading-relaxed">
              {preview.text}
            </pre>
            {preview.truncated && (
              <div className="border-t px-3 py-1 text-xs text-muted-foreground">
                Showing the first part of {formatSize(preview.size)}.
              </div>
            )}
          </div>
        ) : preview.kind === "none" ? (
          <div className="p-4 text-sm text-muted-foreground">
            <div>{preview.reason}</div>
            <div className="mt-1 text-xs">{formatSize(preview.size)}</div>
          </div>
        ) : (
          <pre className="whitespace-pre-wrap p-4 text-xs text-destructive">
            {preview.error}
          </pre>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Run the tests and the typechecker**

Run: `npm test && npm run typecheck`
Expected: both PASS. The typechecker is what proves every `Preview` branch is handled.

- [ ] **Step 3: Build the plugin**

Run: `bb plugin build .`
Expected: `dist/server.js` and `dist/app.js` written with no errors.

- [ ] **Step 4: Commit**

```bash
git add app.tsx
git commit -m "Render the preview pane

Images arrive as real bytes from the plugin's HTTP route rather than
base64 through RPC, so the browser caches them by ETag.

'Too large' and 'cannot preview' are rendered as states rather than
left blank: a pane that says nothing reads as a bug."
```

---

### Task 13: Install, document, and verify against a real host

The first task that requires a human. Nothing before it has touched a remote machine.

**Files:**
- Rewrite: `README.md`
- Delete: `PLUGIN_OVERVIEW.md` (the scaffold's boilerplate)

- [ ] **Step 1: Install the plugin**

```bash
bb plugin install .
bb plugin list | grep remote-files
```
Expected: `remote-files@0.1.0  running`, sourced from this path.

- [ ] **Step 2: Verify the sidebar item appears**

Open BB. Expected: a "Remote Files" item in the sidebar with a folder-tree icon, opening to a connection bar and the message "Set a host and a start directory to begin."

- [ ] **Step 3: Verify the unset state through the CLI**

Run: `bb remote status`
Expected: `target: (unset)`, and no error — unset is a state, not a failure.

- [ ] **Step 4: Connect to a real host**

Use any host reachable by key. Run:

```bash
bb remote use <your-host> <an-absolute-directory>
bb remote connect
bb remote ls
```
Expected: `connect` prints the tier and resize path; `ls` prints the directory.

- [ ] **Step 5: Verify in the panel**

In the Remote Files panel, enter the same host and directory and press Connect. Check each:

- Columns appear, and clicking a directory opens a new column to its right.
- **Clicking a directory in an *earlier* column walks into that directory**,
  rather than merely backing up to the column it lives in. This is the one
  Miller-column gesture with no automated coverage — `app.tsx` has none — so
  it is checked by hand here.
- **A directory you cannot read shows its error in the column**, not an empty
  listing. Make one: `chmod 000` a directory on the remote host, browse to its
  parent, select it, then `chmod` it back. Also untested automatically.
- Typing a host containing letters into the SSH-target field inserts text
  rather than moving the selection.
- `j`/`k` move the selection, `l` descends, `h` ascends, `/` filters.
- Selecting a directory shows its contents in the right-hand pane.
- Selecting a text file shows its text.
- Selecting an image shows the image.
- Selecting an image larger than 2 MB shows it, with the downscaling note when the host has Pillow or ImageMagick.

- [ ] **Step 6: Verify the remote host was left clean**

On the remote host, run:

```bash
ls -la ~ /tmp | grep -i -E 'remote-files|helper|bb-rf'
```
Expected: no output. This is the constraint the whole design exists to satisfy — verify it rather than assume it.

- [ ] **Step 7: Verify the cache filled and is not tracked**

```bash
du -sh .cache
git status --porcelain
```
Expected: `.cache` has content; `git status` shows no `.cache` paths.

- [ ] **Step 8: Rewrite `README.md`**

````markdown
# Remote Files

Browse a remote machine's filesystem from inside BB over nothing but SSH — no
FUSE mount, no SSHFS, and no agent installed on the far side.

The layout is ranger's: a strip of directory columns you walk into, with the
selection previewed on the right. Images preview as images.

## Configuration

The host and start directory are resolved at runtime, most specific first:

1. the panel's fields, or `bb remote use <target> <dir>` — this session only,
   never persisted;
2. the saved `sshTarget` / `rootDir` settings (`bb plugin config remote-files`),
   which BB stores in its own database, not in this checkout;
3. `REMOTE_FILES_SSH_TARGET` and `REMOTE_FILES_ROOT_DIR`, read from the
   environment the bb server was started with;
4. nothing, which the panel reports as unset rather than as an error.

The target accepts `user@host:port`, `host:port`, or an `~/.ssh/config` alias.
Authentication is by key or agent only: ssh runs with `BatchMode=yes`, so a
host that would prompt for a password fails immediately instead of hanging.

Browsing cannot escape the start directory. Paths are resolved to a realpath on
the remote host and checked there, where symlinks actually resolve.

## What runs on the remote host

Nothing is written to remote disk — not a helper, not a temp file, not a cache.

On a host with `python3`, a small helper is streamed to `python3 -` on ssh's
stdin, so it exists only in that process's memory. It produces listings as
JSON and, when Pillow is available, downscales large images in memory so only
the resized bytes cross the wire. On a host without `python3`, listings come
from `find` and `stat` instead; that tier cannot show a filename containing a
newline, and the panel says so.

Connections are multiplexed with ssh's `ControlMaster`, so only the first call
pays for a handshake. The control socket lives in the system temp directory,
not here — Unix socket paths are capped at 104 bytes.

## Cache

Fetched bytes are cached in `.cache/` in this directory, keyed by the remote
file's path, size, and mtime, so a file that changed on the far side misses
rather than serving a stale copy. Least-recently-used blobs are dropped past
the size limit in settings (1 GB by default). `.cache/` is gitignored; delete
it freely.

## CLI

```
bb remote status [--json]     the target, tier, and cache size
bb remote use <target> [dir]  set both for this session only
bb remote connect             connect and probe the host
bb remote ls [path]           list a directory
bb remote cat <path>          print a text file's head
```

## Development

```
npm install --include=dev
npm test                      unit tests, no network
npm run typecheck
bb plugin build .
bb plugin install .
```

The tests never touch a remote host: a fake `ssh` takes the last argument and
runs it under `/bin/sh`, which is what a real ssh does to the far side, so both
host tiers are exercised locally.

## Limits

Read-only: no rename, delete, upload, or download. No video or PDF previews, no
syntax highlighting, one host at a time.
````

- [ ] **Step 9: Delete the scaffold's overview**

```bash
git rm PLUGIN_OVERVIEW.md
```

- [ ] **Step 10: Commit**

```bash
git add README.md
git commit -m "Document the plugin, and drop the scaffold boilerplate

Verified against a real host: the columns, the keyboard, the previews,
and — the point of the whole design — that the far side is left with
nothing on it afterwards."
```

---

## Self-Review

**Spec coverage.** Every section of the design maps to a task: configuration and target parsing to Task 1; transport and multiplexing to Tasks 2 and 3; the capability probe to Task 4; tier A to Task 5; tier B to Task 6; the tier-agnostic client and path confinement to Tasks 5, 6, and 7; the size policy to Task 8; the cache to Task 9; settings, RPC, HTTP byte routes, the CLI, and error handling to Task 10; the Miller-column UI and keyboard to Task 11; the preview pane to Task 12; installation, the README, and the leave-no-trace verification to Task 13.

**Two deliberate deviations from the spec**, both narrowing rather than widening scope:

1. The spec describes remote resizing via `convert - -resize NxN -`. The helper implements the Pillow path only, and `planFetch` returns `whole-then-resize-locally` when Pillow is absent — so an ImageMagick-only host still previews large images, just by transferring them once. Adding the `magick` pipe is a later change to one branch of `RemoteClient.fetch`; the capability probe already detects it.
2. `whole-then-resize-locally` is planned but the local resize is not implemented in Task 10 — `materialize` fetches the whole file and caches it unresized. The image still displays, at full resolution, from cache. Wiring a local downscale is a self-contained follow-up.

Both are noted here rather than left for an implementer to discover.

**Interface consistency.** `Entry` is defined once in `lib/shell-tier.ts` and re-exported through `lib/remote.ts` and `server.ts`; `Capabilities` comes only from `lib/probe.ts`; `cacheKey` takes the same five fields everywhere; `splitHeader` is used by every tier-A call.

**Placeholder scan.** No task contains a TBD, a "handle edge cases", or a test described rather than written. Every code step carries the code it asks for.
