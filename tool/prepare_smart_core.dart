// ignore_for_file: avoid_print
//
// Generates the Smart kernel tree used by this fork.
//
// The repository keeps the official kernel sources untouched in
// core/Clash.Meta. Every build first copies that tree to
// core/.smart-mihomo and applies core/smart.patch (the Smart
// policy-group implementation) to the copy; core/go.mod resolves the
// kernel module to the generated copy, so the official tree is never
// modified and merging upstream releases stays clean.
//
// Any failure aborts the build: shipping a kernel that silently lost
// part of the Smart implementation would be worse than no build.

import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> run(String exe, List<String> args, {String? cwd}) async {
  final result = await Process.run(exe, args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    stderr.writeln('prepare_smart_core: `$exe ${args.join(' ')}` failed');
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    exit(1);
  }
}

void copyTree(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(recursive: false)) {
    final target = p.join(to.path, p.basename(entity.path));
    if (entity is Directory) {
      copyTree(entity, Directory(target));
    } else if (entity is Link) {
      File(entity.targetSync()).copySync(target);
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

Future<void> main() async {
  final root = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..'),
  );
  final source = Directory(p.join(root, 'core', 'Clash.Meta'));
  final generated = Directory(p.join(root, 'core', '.smart-mihomo'));
  final patch = File(p.join(root, 'core', 'smart.patch'));

  if (!source.existsSync() || !patch.existsSync()) {
    stderr.writeln('prepare_smart_core: kernel source or patch missing');
    exit(1);
  }

  if (generated.existsSync()) {
    generated.deleteSync(recursive: true);
  }
  copyTree(source, generated);

  final safeDir = generated.path.replaceAll('\\', '/');
  await run('git', [
    '-c',
    'safe.directory=$safeDir',
    'init',
    '-q',
  ], cwd: generated.path);
  await run('git', [
    '-c',
    'safe.directory=$safeDir',
    'apply',
    '--whitespace=nowarn',
    patch.path,
  ], cwd: generated.path);

  // Sanity check: the Smart implementation must actually be there.
  final marker = File(
    p.join(generated.path, 'adapter', 'outboundgroup', 'smart.go'),
  );
  if (!marker.existsSync()) {
    stderr.writeln('prepare_smart_core: smart.go missing after patching');
    exit(1);
  }
  print('prepare_smart_core: Smart kernel generated in ${generated.path}');
}
