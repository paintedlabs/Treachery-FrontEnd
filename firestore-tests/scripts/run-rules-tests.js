#!/usr/bin/env node
/**
 * Boots the Firestore emulator (port 8098) and runs the mocha rules suite
 * inside it, in one command:  npm test
 *
 * Why this wrapper instead of putting `firebase emulators:exec ...` straight
 * into the npm script (the way Treachery/package.json does for test:e2e):
 * firebase-tools >= 14 refuses to start the emulators on Java < 21, and the
 * default `java` on a dev machine here is 17. Rather than hard-coding one
 * developer's JDK path into package.json, we probe for a Java 21+ runtime and
 * only then hand off to `firebase emulators:exec`. On a CI image where `java`
 * is already 21+ this script is a straight passthrough.
 */

"use strict";

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "demo-rules-test";
const TESTS_DIR = path.resolve(__dirname, "..");
const MIN_JAVA_MAJOR = 21;

/** `java -version` prints to stderr, so both streams have to be inspected. */
function javaMajorVersion(javaBin) {
  const res = spawnSync(javaBin, ["-version"], { encoding: "utf8" });
  if (res.error) return null;
  return parseMajor(`${res.stdout || ""}${res.stderr || ""}`);
}

function parseMajor(text) {
  const match = /version "(\d+)(?:\.(\d+))?/.exec(text || "");
  if (!match) return null;
  const major = Number(match[1]);
  // Legacy scheme: 1.8.x means Java 8
  if (major === 1 && match[2] !== undefined) return Number(match[2]);
  return major;
}

/** Candidate JAVA_HOME directories, most preferred first. */
function candidateJavaHomes() {
  const candidates = [];
  if (process.env.JAVA_HOME) candidates.push(process.env.JAVA_HOME);

  // Homebrew keg-only openjdk formulae, highest version first.
  for (const optDir of [
    "/opt/homebrew/opt",
    "/usr/local/opt",
    "/home/linuxbrew/.linuxbrew/opt",
  ]) {
    let entries;
    try {
      entries = fs.readdirSync(optDir).filter((e) => /^openjdk(@\d+)?$/.test(e));
    } catch {
      continue;
    }
    const suffix = (e) => Number((e.split("@")[1] || "0"));
    entries.sort((a, b) => suffix(b) - suffix(a));
    for (const entry of entries) {
      candidates.push(path.join(optDir, entry, "libexec/openjdk.jdk/Contents/Home"));
      candidates.push(path.join(optDir, entry));
    }
  }

  // Standard JVM install locations.
  for (const jvmDir of ["/Library/Java/JavaVirtualMachines", "/usr/lib/jvm"]) {
    try {
      for (const entry of fs.readdirSync(jvmDir)) {
        candidates.push(path.join(jvmDir, entry, "Contents/Home"));
        candidates.push(path.join(jvmDir, entry));
      }
    } catch {
      /* directory absent on this platform */
    }
  }

  return candidates;
}

function resolveJavaHome() {
  for (const home of candidateJavaHomes()) {
    const bin = path.join(home, "bin", "java");
    if (!fs.existsSync(bin)) continue;
    const major = javaMajorVersion(bin);
    if (major !== null && major >= MIN_JAVA_MAJOR) return { home, major };
  }
  return null;
}

const env = { ...process.env };
const ambient = javaMajorVersion("java");

if (ambient === null || ambient < MIN_JAVA_MAJOR) {
  const found = resolveJavaHome();
  if (!found) {
    console.error(
      `[rules-tests] No Java ${MIN_JAVA_MAJOR}+ runtime found (ambient java: ${ambient ?? "none"}). ` +
        "The Firebase emulators require one — install it (e.g. `brew install openjdk@23`) " +
        "or point JAVA_HOME at a suitable JDK."
    );
    process.exit(1);
  }
  env.JAVA_HOME = found.home;
  env.PATH = `${path.join(found.home, "bin")}${path.delimiter}${env.PATH}`;
  console.log(
    `[rules-tests] ambient java is ${ambient ?? "missing"}; using Java ${found.major} at ${found.home}`
  );
}

const result = spawnSync(
  "npx",
  [
    "--no-install",
    "firebase",
    "emulators:exec",
    `--project=${PROJECT_ID}`,
    "--only",
    "firestore",
    "--config=firebase.json",
    "npx --no-install mocha",
  ],
  { cwd: TESTS_DIR, env, stdio: "inherit" }
);

process.exit(result.status === null ? 1 : result.status);
