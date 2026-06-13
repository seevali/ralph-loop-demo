#!/usr/bin/env node

import { program } from 'commander';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, resolve } from 'path';
import { preflight, renderChecklist } from '../src/preflight.js';
import { classifyTarget } from '../src/classify.js';
import { runWizard } from '../src/wizard.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const packagePath = join(__dirname, '../package.json');
const { version } = JSON.parse(readFileSync(packagePath, 'utf8'));

program
  .version(version, '-v, --version', 'Show version number and exit')
  .helpOption('-h, --help', 'Show help and exit')
  .description('Ralph Loop guided installer — set up a new loop project in minutes');

program
  .command('install')
  .alias('init')
  .description('Install or update a Ralph Loop project')
  .option('-d, --directory <path>', 'Target directory (default: current directory)')
  .action(async (options) => {
    const targetDir = resolve(options.directory ?? '.');

    // Run preflight checks
    const preflightResults = await preflight();
    renderChecklist(preflightResults);

    if (preflightResults.node.status === 'fail') {
      console.error('\nNode.js version check failed. Please upgrade Node.js to >= 20.');
      process.exit(1);
    }
    if (preflightResults.bash.status === 'fail') {
      console.error('\nBash environment check failed. Please install bash (WSL2 or Git Bash on Windows).');
      process.exit(2);
    }

    // Classify target directory
    let classifyResult;
    try {
      classifyResult = await classifyTarget(targetDir);
    } catch (err) {
      console.error(`\nError: ${err.message}`);
      process.exit(1);
    }

    // Run interactive wizard
    const installPlan = await runWizard(targetDir, classifyResult.type, preflightResults);
    if (!installPlan) {
      // User cancelled — exit cleanly (wizard already printed "Nothing was changed.")
      process.exit(0);
    }

    // Story 2.3 will add: await executeInstallPlan(installPlan);
    console.log('\nWizard complete. Install plan ready for write step (Story 2.3).');
  });

program
  .command('update')
  .description('Update an existing Ralph Loop installation')
  .action(() => {
    console.log('update: not yet implemented');
    process.exit(0);
  });

program
  .command('uninstall')
  .description('Remove a Ralph Loop installation')
  .action(() => {
    console.log('uninstall: not yet implemented');
    process.exit(0);
  });

program
  .command('doctor')
  .description('Validate an existing Ralph Loop installation')
  .action(() => {
    console.log('doctor: not yet implemented');
    process.exit(0);
  });

program.parse(process.argv);

if (process.argv.length === 2) {
  program.outputHelp();
  process.exit(0);
}
