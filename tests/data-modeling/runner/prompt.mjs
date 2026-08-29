// Assemble the evaluation prompt for a case: the skill content + case input.
// Shared by run.mjs so prompt construction stays in one place.

import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const skillDir = join(here, '..', '..', '..', 'skills', 'data-modeling');

// Files the model-under-test receives, in order. Keep this aligned with what
// an agent would realistically load after triggering the skill.
const SKILL_FILES = [
  'SKILL.md',
  'references/workflow.md',
  'references/crdt-types.md',
  'references/versions.md',
  'references/performance.md',
  'best-practices.md',
];

export async function buildPrompt(caseDir) {
  const [inputRaw, expectedRaw] = await Promise.all([
    readFile(join(caseDir, 'input.json'), 'utf8'),
    readFile(join(caseDir, 'expected.json'), 'utf8'),
  ]);
  const expected = JSON.parse(expectedRaw);

  const skillParts = [];
  for (const rel of SKILL_FILES) {
    const body = await readFile(join(skillDir, rel), 'utf8');
    skillParts.push(`<skill-file path="skills/data-modeling/${rel}">\n${body}\n</skill-file>`);
  }

  const prompt = `You are a Ditto data-modeling expert. Below is the complete guidance of the "data-modeling" skill (everything between <skill-file> tags), followed by a user's request. Follow the skill's workflow exactly: findings with rubric IDs, the recommended model, split decisions, and budget notes.

${skillParts.join('\n\n')}

<user-request>
Review this JSON document as a candidate Ditto data model and recommend improvements.

Deployment context:
${expected.context}

Document:
\`\`\`json
${inputRaw.trim()}
\`\`\`

Respond in the skill's output format (## Findings / ## Recommended model / ## Split decisions / ## Budget). Cite the rubric finding IDs (e.g. ARRAY_LWW, COUNTER_CANDIDATE) verbatim, with severity, the JSON path, and a one-line reason for each finding. Tag any version-gated recommendation with its minimum SDK version.
</user-request>`;

  return { prompt, expected };
}
