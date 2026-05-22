import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const maxLineLength = 800;
const skillPath = ".agents/skills/visionos-platform/SKILL.md";
const referencesDir = ".agents/skills/visionos-platform/references";

const requiredReferenceSections = [
  "## Apple Sources",
  "### Open first",
  "### Open if",
  "## Correct Decisions",
  "## iOS/macOS Conflicts",
  "## Enchron Checkpoints",
];

const errors: string[] = [];

function readLines(path: string): string[] {
  if (!existsSync(path)) {
    errors.push(`Missing file: ${path}`);
    return [];
  }

  return readFileSync(path, "utf8").split(/\r?\n/);
}

function checkLineLengths(path: string): void {
  readLines(path).forEach((line, index) => {
    if (line.length > maxLineLength) {
      errors.push(
        `${path}:${index + 1} exceeds ${maxLineLength} characters (${line.length})`,
      );
    }
  });
}

function checkSkillFrontMatter(): void {
  const lines = readLines(skillPath);
  if (lines.length === 0) return;

  if (lines[0] !== "---") {
    errors.push(`${skillPath}:1 must be a standalone front matter delimiter`);
  }

  const closingIndex = lines.indexOf("---", 1);
  if (closingIndex === -1) {
    errors.push(`${skillPath}: missing closing front matter delimiter`);
    return;
  }

  const frontMatter = lines.slice(1, closingIndex);
  if (!frontMatter.some((line) => line.startsWith("name: "))) {
    errors.push(`${skillPath}: front matter must include name`);
  }

  if (!frontMatter.some((line) => line.startsWith("description: "))) {
    errors.push(`${skillPath}: front matter must include description`);
  }
}

function checkReferenceSections(): void {
  const referenceFiles = readdirSync(referencesDir)
    .filter((name) => name.endsWith(".md"))
    .filter((name) => name !== "misconceptions.md")
    .map((name) => join(referencesDir, name));

  for (const path of referenceFiles) {
    const text = readFileSync(path, "utf8");
    for (const section of requiredReferenceSections) {
      if (!text.includes(`${section}\n`)) {
        errors.push(`${path}: missing section "${section}"`);
      }
    }
  }
}

function main(): void {
  checkSkillFrontMatter();
  checkLineLengths("AGENTS.md");
  checkLineLengths(skillPath);

  for (const name of readdirSync(referencesDir)) {
    if (name.endsWith(".md")) {
      checkLineLengths(join(referencesDir, name));
    }
  }

  checkReferenceSections();

  if (errors.length > 0) {
    console.error(errors.join("\n"));
    process.exit(1);
  }

  console.log("visionOS skill docs guard passed");
}

main();
