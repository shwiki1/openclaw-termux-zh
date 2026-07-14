/**
 * Basic tests for CiYuanXia compatibility CLI
 * Tests module loading, exports, and basic functionality
 */

import { strict as assert } from 'node:assert';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { existsSync, readFileSync } from 'node:fs';
import os from 'node:os';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, '..');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (error) {
    console.log(`  ✗ ${name}`);
    console.log(`    ${error.message}`);
    failed++;
  }
}

async function testAsync(name, fn) {
  try {
    await fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (error) {
    console.log(`  ✗ ${name}`);
    console.log(`    ${error.message}`);
    failed++;
  }
}

async function runTests() {
  console.log('\n🧪 CiYuanXia compatibility CLI tests\n');

  // File existence tests
  console.log('📁 File Structure:');

  test('bin/openclawx exists', () => {
    assert.ok(existsSync(join(projectRoot, 'bin/openclawx')));
  });

  test('lib/index.js exists', () => {
    assert.ok(existsSync(join(projectRoot, 'lib/index.js')));
  });

  test('lib/installer.js exists', () => {
    assert.ok(existsSync(join(projectRoot, 'lib/installer.js')));
  });

  test('lib/bionic-bypass.js exists', () => {
    assert.ok(existsSync(join(projectRoot, 'lib/bionic-bypass.js')));
  });

  test('package.json exists', () => {
    assert.ok(existsSync(join(projectRoot, 'package.json')));
  });

  // Module import tests
  console.log('\n📦 Module Imports:');

  await testAsync('index.js exports main function', async () => {
    const indexModule = await import('./index.js');
    assert.ok(typeof indexModule.main === 'function');
  });

  await testAsync('installer.js exports setup functions', async () => {
    const installerModule = await import('./installer.js');
    assert.ok(typeof installerModule.setupProotUbuntu === 'function');
    assert.ok(typeof installerModule.installProot === 'function');
    assert.ok(typeof installerModule.getInstallStatus === 'function');
  });

  await testAsync('bionic-bypass.js loads without error', async () => {
    await import('./bionic-bypass.js');
  });

  // Package.json validation
  console.log('\n📋 Package Configuration:');

  test('package.json has required fields', () => {
    const pkg = JSON.parse(readFileSync(join(projectRoot, 'package.json'), 'utf8'));
    assert.ok(pkg.name === 'ciyuanxia');
    assert.ok(pkg.version);
    assert.ok(pkg.main);
    assert.ok(pkg.bin);
    assert.ok(pkg.bin.openclawx);
  });

  test('package.json specifies node engine >= 18', () => {
    const pkg = JSON.parse(readFileSync(join(projectRoot, 'package.json'), 'utf8'));
    assert.ok(pkg.engines?.node);
    const minVersion = parseInt(pkg.engines.node.match(/\d+/)[0]);
    assert.ok(minVersion >= 18, 'Node.js version should be >= 18');
  });

  console.log('\n📱 Android Versioning:');

  test('Gradle uses an install-visible base+build versionName', () => {
    const gradle = readFileSync(
      join(projectRoot, 'flutter_app/android/app/build.gradle'),
      'utf8',
    );
    assert.ok(gradle.includes('flutter.androidVersionName'));
    assert.match(gradle, /versionName\s*=\s*androidVersionName/);
  });

  test('settings screen does not append split APK versionCode', () => {
    const settingsScreen = readFileSync(
      join(projectRoot, 'flutter_app/lib/screens/settings_screen.dart'),
      'utf8',
    );
    assert.ok(!settingsScreen.includes('versionCode'));
    assert.ok(settingsScreen.includes('? versionName'));
  });

  console.log('\n🧩 Runtime Versioning:');

  test('Node runtime defaults match bundled resource version', () => {
    const expectedNodeVersion = '24.14.1';
    const staleNodeVersion = ['24', '15', '0'].join('.');
    const checkedFiles = [
      'flutter_app/lib/constants.dart',
      'scripts/build-prebuilt-rootfs.sh',
      'scripts/prebuilt-rootfs-metadata.sh',
      'flutter_app/lib/l10n/app_strings_en.dart',
      'flutter_app/lib/l10n/app_strings_ja.dart',
      'flutter_app/lib/l10n/app_strings_zh_hans.dart',
      'flutter_app/lib/l10n/app_strings_zh_hant.dart',
      'flutter_app/assets/bootstrap/README.md',
      'flutter_app/assets/bootstrap/basic-resource-release.zh.md',
      'README.md',
      'docs/README_en.md',
      'STRUCTURE.md',
      'CHANGELOG.md',
      'lib/installer.js',
    ];

    for (const relativePath of checkedFiles) {
      const contents = readFileSync(join(projectRoot, relativePath), 'utf8');
      assert.ok(
        contents.includes(expectedNodeVersion),
        `${relativePath} should reference Node.js ${expectedNodeVersion}`,
      );
      assert.ok(
        !contents.includes(staleNodeVersion),
        `${relativePath} should not reference stale Node.js ${staleNodeVersion}`,
      );
    }

    assert.ok(
      existsSync(
        join(
          projectRoot,
          'flutter_app/assets/bootstrap/node-v24.14.1-linux-arm64.tar.xz',
        ),
      ),
      'bundled Node.js fallback archive should exist',
    );
  });

  // Bionic bypass functionality
  console.log('\n🔧 Bionic Bypass:');

  test('os.networkInterfaces returns object after bypass', () => {
    const interfaces = os.networkInterfaces();
    assert.ok(typeof interfaces === 'object');
  });

  // Summary
  console.log('\n' + '─'.repeat(40));
  console.log(`\n📊 Results: ${passed} passed, ${failed} failed\n`);

  if (failed > 0) {
    process.exit(1);
  }
}

runTests();
