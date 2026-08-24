import { cp, mkdir, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const resources = resolve(root, "src-tauri", "resources");
const skillsDestination = resolve(resources, "codex-skills");

await mkdir(resources, { recursive: true });
await cp(resolve(root, "bridge.md"), resolve(resources, "bridge.md"));
await rm(skillsDestination, { recursive: true, force: true });
await cp(resolve(root, "codex-skills"), skillsDestination, { recursive: true });

console.log(`Copied Tauri resources to ${resources}`);
