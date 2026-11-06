import { execSync } from "node:child_process";

try {
  const output = execSync("npx tauri info", { encoding: "utf8" });
  if (output.includes("Found version mismatched Tauri packages")) {
    console.error("[-] Tauri version mismatch detected:\n", output);
    process.exit(1);
  }
  console.log("[+] Tauri package versions match!");
} catch (error) {
  const output = String(error.stdout || "") + String(error.stderr || "");
  if (output.includes("Found version mismatched Tauri packages")) {
    console.error("[-] Tauri version mismatch detected:\n", output);
    process.exit(1);
  }
  throw error;
}
