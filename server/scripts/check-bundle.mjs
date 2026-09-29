import { spawn, spawnSync } from "node:child_process";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer } from "node:net";

// Exercise the browser script emitted by Wrangler, not only its TypeScript source.
const socket = createServer();
await new Promise(resolve => socket.listen(0, "127.0.0.1", resolve));
const port = socket.address().port;
await new Promise(resolve => socket.close(resolve));
const folder = await mkdtemp(join(tmpdir(), "mealshuffler-bundle-"));
const worker = spawn(process.execPath, ["node_modules/wrangler/bin/wrangler.js", "dev", "--local", "--ip", "127.0.0.1", "--port", String(port)], {
  stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, WRANGLER_SEND_METRICS: "false" },
});
let logs = "";
worker.stdout.on("data", chunk => { logs += chunk; });
worker.stderr.on("data", chunk => { logs += chunk; });
try {
  let script;
  const deadline = Date.now() + 45_000;
  while (Date.now() < deadline) {
    if (worker.exitCode !== null) throw new Error(logs);
    try {
      const response = await fetch(`http://127.0.0.1:${port}/s/app.js`, { signal: AbortSignal.timeout(2_000) });
      if (response.ok) { script = await response.text(); break; }
    } catch { /* Worker is still starting. */ }
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  if (!script) throw new Error(`Worker did not start.\n${logs}`);
  const path = join(folder, "share.js");
  await writeFile(path, script);
  const result = spawnSync(process.execPath, ["--experimental-strip-types", "--test", "test/share.test.ts"], {
    stdio: "inherit", env: { ...process.env, SHARE_SCRIPT_PATH: path },
  });
  process.exitCode = result.status ?? 1;
} finally {
  if (process.platform === "win32") spawnSync("taskkill", ["/pid", String(worker.pid), "/t", "/f"], { stdio: "ignore" });
  else worker.kill("SIGTERM");
  await rm(folder, { recursive: true, force: true });
}
