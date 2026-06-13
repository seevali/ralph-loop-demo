import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runWizard, validators } from './wizard.js';

// A unique symbol that acts as the @clack/prompts cancel token in tests.
const CANCEL = Symbol('test:cancel');

/**
 * Build a mock prompts bundle that auto-answers every prompt with its
 * initialValue (or the first option for select).  Override specific call
 * indices via { confirms, texts, selects } arrays.
 */
function buildMockPrompts(overrides = {}) {
  const counts = { confirm: 0, text: 0, select: 0 };
  return {
    intro: () => {},
    outro: () => {},
    isCancel: (v) => v === CANCEL,
    cancel: () => {},
    confirm: async (opts) => overrides.confirms?.[counts.confirm++] ?? opts.initialValue ?? true,
    select: async (opts) =>
      overrides.selects?.[counts.select++] ?? opts.initialValue ?? opts.options[0].value,
    text: async (opts) => overrides.texts?.[counts.text++] ?? opts.initialValue ?? '',
  };
}

// ─── Happy path ───────────────────────────────────────────────────────────────

test('returns a valid InstallPlan with all required fields (Enter-only defaults)', async () => {
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, { prompts: buildMockPrompts() });

  assert.ok(plan, 'plan should be defined');
  assert.equal(plan.targetDir, '/tmp/test-dir');
  assert.equal(plan.classification, 'empty');
  assert.equal(plan.isUpdate, false);
  assert.equal(plan.appDir, 'src');
  assert.ok(plan.checkpointCommand, 'checkpointCommand should be non-empty');
  assert.ok(plan.stackDescription, 'stackDescription should be non-empty');
  assert.equal(plan.loopRetries, 3);
  assert.equal(plan.maxTokensPerTurn, 200000);
  assert.deepEqual(plan.modelOrder, ['opus', 'sonnet', 'haiku']);
  assert.equal(plan.taskSource, 'scaffold');
  assert.equal(plan.taskSourcePath, undefined);
  assert.equal(plan.addGitignoreEntries, true);
  assert.deepEqual(plan.gitignoreEntries, ['_bmad/', '.claude/skills/', 'scripts/logs/']);
  assert.equal(plan.addNpmScripts, true);
  assert.deepEqual(plan.npmScriptNames, ['dev-story', 'code-review']);
  assert.ok(plan.wizardAnswers, 'wizardAnswers should be present');
  assert.equal(plan.wizardAnswers.explainerConfirmed, true);
  assert.ok(Array.isArray(plan.summaryLines), 'summaryLines should be an array');
  assert.ok(plan.summaryLines.length > 0, 'summaryLines should not be empty');
});

test('all string fields are non-empty after trimming (defaults)', async () => {
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, { prompts: buildMockPrompts() });
  for (const key of ['appDir', 'checkpointCommand', 'stackDescription']) {
    assert.ok(plan[key].trim().length > 0, `plan.${key} should be non-empty after trim`);
  }
});

test('numeric fields are integers >= 0', async () => {
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, { prompts: buildMockPrompts() });
  assert.ok(Number.isInteger(plan.loopRetries) && plan.loopRetries >= 0, 'loopRetries >= 0');
  assert.ok(Number.isInteger(plan.maxTokensPerTurn) && plan.maxTokensPerTurn > 0, 'maxTokensPerTurn > 0');
});

// ─── Classification variants ──────────────────────────────────────────────────

test('isUpdate is true when classification is existing-install', async () => {
  const plan = await runWizard('/tmp/test-dir', 'existing-install', {}, {
    prompts: buildMockPrompts(),
  });
  assert.equal(plan.isUpdate, true);
  assert.equal(plan.classification, 'existing-install');
});

test('isUpdate is false when classification is existing-project', async () => {
  const plan = await runWizard('/tmp/test-dir', 'existing-project', {}, {
    prompts: buildMockPrompts(),
  });
  assert.equal(plan.isUpdate, false);
});

// ─── Task source ──────────────────────────────────────────────────────────────

test('taskSourcePath is set when user selects existing task source', async () => {
  // confirm x5 (defaults), select returns 'existing', texts: appDir, checkpoint, stack, retries, tokens, prdPath
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, {
    prompts: buildMockPrompts({
      selects: ['existing'],
      texts: ['src', 'npm run build && npm test', 'React + TypeScript', '3', '200000', 'my/prd.md'],
    }),
  });
  assert.equal(plan.taskSource, 'existing');
  assert.equal(plan.taskSourcePath, 'my/prd.md');
});

test('taskSourcePath is undefined when user selects scaffold', async () => {
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, {
    prompts: buildMockPrompts({ selects: ['scaffold'] }),
  });
  assert.equal(plan.taskSource, 'scaffold');
  assert.equal(plan.taskSourcePath, undefined);
});

// ─── Extras opt-out ───────────────────────────────────────────────────────────

test('gitignoreEntries is empty when user opts out', async () => {
  // confirms: explainer, target, addGitignore=false, addNpmScripts, finalConfirm
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, {
    prompts: buildMockPrompts({ confirms: [true, true, false, true, true] }),
  });
  assert.equal(plan.addGitignoreEntries, false);
  assert.deepEqual(plan.gitignoreEntries, []);
});

test('npmScriptNames is empty when user opts out', async () => {
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, {
    prompts: buildMockPrompts({ confirms: [true, true, true, false, true] }),
  });
  assert.equal(plan.addNpmScripts, false);
  assert.deepEqual(plan.npmScriptNames, []);
});

// ─── Cancellation handling ────────────────────────────────────────────────────

test('Ctrl-C at explainer prompt calls exit(0) and returns undefined', async () => {
  const exitCalls = [];
  const result = await runWizard('/tmp/test-dir', 'empty', {}, {
    exit: (code) => exitCalls.push(code),
    prompts: {
      intro: () => {},
      outro: () => {},
      isCancel: (v) => v === CANCEL,
      cancel: () => {},
      confirm: async () => CANCEL,
      select: async (opts) => opts.initialValue ?? opts.options[0].value,
      text: async (opts) => opts.initialValue ?? '',
    },
  });

  assert.equal(result, undefined, 'should return undefined on cancel');
  assert.equal(exitCalls.length, 1, 'exit should be called once');
  assert.equal(exitCalls[0], 0, 'exit should be called with code 0');
});

test('declining at final confirmation calls exit(0) and returns undefined', async () => {
  const exitCalls = [];
  let confirmCount = 0;

  const result = await runWizard('/tmp/test-dir', 'empty', {}, {
    exit: (code) => exitCalls.push(code),
    prompts: {
      intro: () => {},
      outro: () => {},
      isCancel: () => false,
      cancel: () => {},
      // Return false on the 5th confirm (index 4) — the final "Create this install?"
      confirm: async (opts) => (confirmCount++ === 4 ? false : (opts.initialValue ?? true)),
      select: async (opts) => opts.initialValue ?? opts.options[0].value,
      text: async (opts) => opts.initialValue ?? '',
    },
  });

  assert.equal(result, undefined, 'should return undefined on decline');
  assert.equal(exitCalls.length, 1, 'exit should be called once');
  assert.equal(exitCalls[0], 0, 'exit should be called with code 0');
});

test('Ctrl-C mid-wizard calls exit(0) and returns undefined', async () => {
  const exitCalls = [];
  let textCount = 0;

  const result = await runWizard('/tmp/test-dir', 'empty', {}, {
    exit: (code) => exitCalls.push(code),
    prompts: {
      intro: () => {},
      outro: () => {},
      isCancel: (v) => v === CANCEL,
      cancel: () => {},
      confirm: async (opts) => opts.initialValue ?? true,
      select: async (opts) => opts.initialValue ?? opts.options[0].value,
      // Cancel on the second text prompt (checkpoint command)
      text: async (opts) => (textCount++ === 1 ? CANCEL : (opts.initialValue ?? '')),
    },
  });

  assert.equal(result, undefined, 'should return undefined on cancel');
  assert.equal(exitCalls.length, 1);
  assert.equal(exitCalls[0], 0);
});

// ─── Non-TTY detection ────────────────────────────────────────────────────────

test('throws when no TTY and no injected prompts', async () => {
  const origIsTTY = process.stdin.isTTY;
  try {
    Object.defineProperty(process.stdin, 'isTTY', { value: false, configurable: true });
    await assert.rejects(
      () => runWizard('/tmp/test-dir', 'empty', {}),
      (err) => {
        assert.ok(err.message.includes('interactive terminal'), 'error should mention TTY');
        return true;
      },
    );
  } finally {
    Object.defineProperty(process.stdin, 'isTTY', {
      value: origIsTTY,
      configurable: true,
    });
  }
});

// ─── InstallPlan schema completeness ─────────────────────────────────────────

test('InstallPlan schema: all required top-level keys are present', async () => {
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, { prompts: buildMockPrompts() });
  const requiredKeys = [
    'targetDir', 'classification', 'isUpdate',
    'appDir', 'checkpointCommand', 'stackDescription',
    'loopRetries', 'maxTokensPerTurn', 'modelOrder',
    'taskSource',
    'addGitignoreEntries', 'gitignoreEntries',
    'addNpmScripts', 'npmScriptNames',
    'wizardAnswers', 'summaryLines',
  ];
  for (const key of requiredKeys) {
    assert.ok(key in plan, `plan.${key} should be present`);
  }
});

test('InstallPlan schema: wizardAnswers contains required flags', async () => {
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, { prompts: buildMockPrompts() });
  assert.equal(typeof plan.wizardAnswers.explainerConfirmed, 'boolean');
  assert.equal(typeof plan.wizardAnswers.stackConfirmed, 'boolean');
  assert.equal(typeof plan.wizardAnswers.loopKnobsConfirmed, 'boolean');
});

test('InstallPlan schema: modelOrder is an array of strings', async () => {
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, { prompts: buildMockPrompts() });
  assert.ok(Array.isArray(plan.modelOrder));
  assert.ok(plan.modelOrder.every((m) => typeof m === 'string'));
});

// ─── validators.appDir ───────────────────────────────────────────────────────

test('validators.appDir: rejects empty string', () => {
  assert.ok(validators.appDir(''), 'empty string should be invalid');
  assert.ok(validators.appDir('   '), 'whitespace-only should be invalid');
});

test('validators.appDir: rejects absolute paths', () => {
  assert.ok(validators.appDir('/src'), 'leading slash should be invalid');
  assert.ok(validators.appDir('/usr/local'), 'absolute path should be invalid');
});

test('validators.appDir: rejects path traversal', () => {
  assert.ok(validators.appDir('../outside'), '.. should be invalid');
  assert.ok(validators.appDir('src/../secret'), 'embedded .. should be invalid');
});

test('validators.appDir: accepts valid relative paths', () => {
  assert.equal(validators.appDir('src'), undefined, '"src" should be valid');
  assert.equal(validators.appDir('packages/ui'), undefined, '"packages/ui" should be valid');
  assert.equal(validators.appDir('  frontend  '), undefined, 'whitespace is trimmed before check');
});

// ─── validators.checkpointCommand ────────────────────────────────────────────

test('validators.checkpointCommand: rejects empty and whitespace', () => {
  assert.ok(validators.checkpointCommand(''), 'empty should be invalid');
  assert.ok(validators.checkpointCommand('   '), 'whitespace-only should be invalid');
});

test('validators.checkpointCommand: accepts any non-empty command', () => {
  assert.equal(validators.checkpointCommand('npm run build && npm test'), undefined);
  assert.equal(validators.checkpointCommand('make test'), undefined);
  assert.equal(
    validators.checkpointCommand('bash -n script.sh && ./script.sh --dry-run'),
    undefined,
  );
});

// ─── validators.loopRetries ──────────────────────────────────────────────────

test('validators.loopRetries: rejects non-numeric and negative', () => {
  assert.ok(validators.loopRetries('abc'));
  assert.ok(validators.loopRetries(''));
  assert.ok(validators.loopRetries('-1'));
});

test('validators.loopRetries: accepts 0 and positive integers', () => {
  assert.equal(validators.loopRetries('0'), undefined);
  assert.equal(validators.loopRetries('3'), undefined);
  assert.equal(validators.loopRetries('10'), undefined);
});

// ─── validators.maxTokensPerTurn ─────────────────────────────────────────────

test('validators.maxTokensPerTurn: rejects 0 and negative', () => {
  assert.ok(validators.maxTokensPerTurn('0'));
  assert.ok(validators.maxTokensPerTurn('-1'));
  assert.ok(validators.maxTokensPerTurn(''));
});

test('validators.maxTokensPerTurn: accepts positive integers', () => {
  assert.equal(validators.maxTokensPerTurn('200000'), undefined);
  assert.equal(validators.maxTokensPerTurn('1'), undefined);
});

// ─── validators.stackDescription ─────────────────────────────────────────────

test('validators.stackDescription: rejects empty/whitespace', () => {
  assert.ok(validators.stackDescription(''));
  assert.ok(validators.stackDescription('   '));
});

test('validators.stackDescription: accepts strings with special characters', () => {
  assert.equal(validators.stackDescription('React 19 + Vite + TypeScript'), undefined);
  assert.equal(validators.stackDescription('Node.js # markdown * chars'), undefined);
  assert.equal(validators.stackDescription('multi\nline\ncontent'), undefined);
});

// ─── Edge cases ───────────────────────────────────────────────────────────────

test('edge case: whitespace-padded text inputs are trimmed in InstallPlan', async () => {
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, {
    prompts: buildMockPrompts({
      texts: ['  src  ', '  npm test  ', '  React  ', '3', '200000'],
    }),
  });
  assert.equal(plan.appDir, 'src', 'appDir should be trimmed');
  assert.equal(plan.checkpointCommand, 'npm test', 'checkpointCommand should be trimmed');
  assert.equal(plan.stackDescription, 'React', 'stackDescription should be trimmed');
});

test('edge case: stack description with markdown special characters is stored as-is', async () => {
  const rawStack = 'React 19 + **Vite** + TypeScript\n# Strict mode\n* CSS Modules';
  const plan = await runWizard('/tmp/test-dir', 'empty', {}, {
    prompts: buildMockPrompts({ texts: ['src', 'npm test', rawStack, '3', '200000'] }),
  });
  assert.equal(plan.stackDescription, rawStack.trim(), 'stack description stored verbatim');
});
