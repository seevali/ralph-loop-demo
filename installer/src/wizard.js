import { intro, outro, text, confirm, select, isCancel } from '@clack/prompts';
import pc from 'picocolors';

// Sentinel thrown internally when the user cancels or declines.
// The outer try-catch converts it to a clean undefined return.
const CANCELLED = Symbol('wizard:cancelled');

// Validators exported so tests can verify them independently.
export const validators = {
  appDir(value) {
    const trimmed = value.trim();
    if (!trimmed) return 'Directory name is required.';
    if (trimmed.startsWith('/') || trimmed.includes('..')) {
      return 'Use a relative path (e.g., src, packages/ui).';
    }
    return undefined;
  },

  checkpointCommand(value) {
    const trimmed = value.trim();
    if (!trimmed) return 'Checkpoint command is required.';
    return undefined;
  },

  stackDescription(value) {
    if (!value.trim()) return 'Stack description is required.';
    return undefined;
  },

  loopRetries(value) {
    const num = parseInt(value.trim(), 10);
    if (isNaN(num) || num < 0) return 'Enter a non-negative number.';
    return undefined;
  },

  maxTokensPerTurn(value) {
    const num = parseInt(value.trim(), 10);
    if (isNaN(num) || num <= 0) return 'Enter a positive number.';
    return undefined;
  },

  taskSourcePath(value) {
    if (!value.trim()) return 'Path is required.';
    return undefined;
  },
};

function makeCancelChecker(p, exit) {
  return function checkCancel(value) {
    if (p.isCancel(value)) {
      p.outro(pc.yellow('Nothing was changed.'));
      exit(0);
      throw CANCELLED;
    }
    return value;
  };
}

function decline(p, exit) {
  p.outro(pc.yellow('Nothing was changed.'));
  exit(0);
  throw CANCELLED;
}

/**
 * Run the interactive wizard to collect install configuration.
 *
 * @param {string} targetDir - absolute path to the target directory
 * @param {'empty'|'existing-project'|'existing-install'} classification - from Story 2.1
 * @param {object} preflightResults - from Story 1.4's preflight()
 * @param {object} [opts]
 * @param {object}   [opts.prompts] - injectable prompt functions (for testing)
 * @param {Function} [opts.exit]    - injectable process.exit (for testing)
 * @returns {Promise<object|undefined>} InstallPlan, or undefined if user cancelled
 */
export async function runWizard(targetDir, classification, preflightResults, opts = {}) {
  // @clack/prompts requires a real TTY. Story 3.1 adds --yes for non-interactive mode.
  if (!opts.prompts && !process.stdin.isTTY) {
    throw new Error(
      'Wizard requires an interactive terminal. Use --yes for non-interactive mode (Story 3.1).',
    );
  }

  const p = opts.prompts ?? { intro, outro, text, confirm, select, isCancel };
  const exit = opts.exit ?? process.exit;
  const checkCancel = makeCancelChecker(p, exit);

  try {
    // ── Step 2: Intro ──────────────────────────────────────────────────────────
    p.intro(pc.bold('Ralph Loop Guided Installer'));

    const explainerConfirmed = checkCancel(
      await p.confirm({
        message:
          'Welcome! This wizard will set up the Ralph Loop — an agent-driven development loop\n' +
          'running Claude Code to build your app story by story.\n\n' +
          "We'll collect information about your project and the loop configuration.\n" +
          'Press Enter to accept any default, or Ctrl-C to cancel (zero changes made).\n\n' +
          'Continue?',
        initialValue: true,
      }),
    );
    if (!explainerConfirmed) decline(p, exit);

    // ── Step 3: Target directory confirmation ─────────────────────────────────
    const targetMessage =
      classification === 'empty'
        ? "This directory is empty. I can initialize git and create a skeleton."
        : classification === 'existing-project'
          ? "This is an existing project. I'll add Ralph Loop files without touching your code."
          : "This directory already has a Ralph Loop install. I'll update it.";

    const targetConfirmed = checkCancel(
      await p.confirm({
        message: `${targetMessage}\n\nTarget: ${targetDir}\n\nContinue?`,
        initialValue: true,
      }),
    );
    if (!targetConfirmed) decline(p, exit);

    // ── Step 4a: App directory ────────────────────────────────────────────────
    const appDirRaw = checkCancel(
      await p.text({
        message: 'Application source directory (relative to project root)',
        initialValue: 'src',
        validate: validators.appDir,
      }),
    );

    // ── Step 4b: Checkpoint command ───────────────────────────────────────────
    const checkpointCommandRaw = checkCancel(
      await p.text({
        message: 'Checkpoint command (build + test; shown in loop prompts)',
        initialValue: 'npm run build && npm test',
        validate: validators.checkpointCommand,
      }),
    );

    // ── Step 4c: Stack description ────────────────────────────────────────────
    // @clack/prompts text is single-line by default. Multi-line content can be
    // edited in the generated project-conventions.md after install.
    const stackDescriptionRaw = checkCancel(
      await p.text({
        message: 'Stack description (tech choices, testing approach, etc.)',
        initialValue:
          'React 19 + Vite + TypeScript (strict mode)\nCSS Modules for styling\nVitest + React Testing Library for tests\nFetch API for HTTP',
        validate: validators.stackDescription,
      }),
    );

    // ── Step 5: Loop knobs ────────────────────────────────────────────────────
    const loopRetriesRaw = checkCancel(
      await p.text({
        message: 'Max retries per agent invocation (recommended: 3–5)',
        initialValue: '3',
        validate: validators.loopRetries,
      }),
    );

    const maxTokensPerTurnRaw = checkCancel(
      await p.text({
        message: 'Max output tokens per loop turn (recommended: 150k–300k)',
        initialValue: '200000',
        validate: validators.maxTokensPerTurn,
      }),
    );

    // ── Step 6: Task source ───────────────────────────────────────────────────
    const taskSource = checkCancel(
      await p.select({
        message: 'How would you like to define the first task?',
        options: [
          {
            value: 'scaffold',
            label: 'Start with a template PRD and epic (recommended)',
            hint: 'Includes comments explaining the format',
          },
          {
            value: 'existing',
            label: 'Point to an existing PRD and epic',
            hint: 'Must follow the ### Story X.Y: Title format',
          },
        ],
        initialValue: 'scaffold',
      }),
    );

    let taskSourcePath;
    if (taskSource === 'existing') {
      taskSourcePath = checkCancel(
        await p.text({
          message: 'Path to your PRD file (relative to project root)',
          initialValue: 'docs/prd.md',
          validate: validators.taskSourcePath,
        }),
      );
    }

    // ── Step 7: Extras ────────────────────────────────────────────────────────
    const addGitignoreEntries = checkCancel(
      await p.confirm({
        message: 'Add default .gitignore entries (_bmad/, .claude/skills/, scripts/logs/)?',
        initialValue: true,
      }),
    );

    const addNpmScripts = checkCancel(
      await p.confirm({
        message: 'Add npm scripts for the loop (dev-story, code-review)?',
        initialValue: true,
      }),
    );

    const gitignoreEntries = addGitignoreEntries
      ? ['_bmad/', '.claude/skills/', 'scripts/logs/']
      : [];

    const npmScriptNames = addNpmScripts ? ['dev-story', 'code-review'] : [];

    // ── Step 8: Summary and final confirmation ────────────────────────────────
    const summaryLines = [
      `Target directory: ${targetDir}`,
      `App directory: ${appDirRaw.trim()}`,
      `Checkpoint command: ${checkpointCommandRaw.trim()}`,
      `Stack: ${stackDescriptionRaw.trim().split('\n')[0]}...`,
      `Task source: ${taskSource}`,
      `Loop retries: ${loopRetriesRaw.trim()}`,
      `Max tokens: ${maxTokensPerTurnRaw.trim()}`,
      addGitignoreEntries ? 'Will add .gitignore entries' : 'No .gitignore changes',
      addNpmScripts ? 'Will add npm scripts' : 'No npm script changes',
    ];

    console.log('\n' + pc.gray('Plan summary:'));
    summaryLines.forEach((line) => console.log('  ' + line));

    const finalConfirm = checkCancel(
      await p.confirm({
        message: 'Create this install?',
        initialValue: true,
      }),
    );
    if (!finalConfirm) decline(p, exit);

    // ── Step 9: Build and return the InstallPlan ──────────────────────────────
    const installPlan = {
      targetDir,
      classification,
      isUpdate: classification === 'existing-install',

      appDir: appDirRaw.trim(),
      checkpointCommand: checkpointCommandRaw.trim(),
      stackDescription: stackDescriptionRaw.trim(),

      loopRetries: parseInt(loopRetriesRaw.trim(), 10),
      maxTokensPerTurn: parseInt(maxTokensPerTurnRaw.trim(), 10),
      modelOrder: ['opus', 'sonnet', 'haiku'],

      taskSource,
      taskSourcePath: taskSourcePath?.trim(),

      addGitignoreEntries,
      gitignoreEntries,
      addNpmScripts,
      npmScriptNames,

      wizardAnswers: {
        explainerConfirmed: true,
        stackConfirmed: true,
        loopKnobsConfirmed: true,
      },

      summaryLines,
    };

    p.outro(pc.green('Plan ready. Proceeding to install...'));

    return installPlan;
  } catch (err) {
    if (err === CANCELLED) return undefined;
    throw err;
  }
}
