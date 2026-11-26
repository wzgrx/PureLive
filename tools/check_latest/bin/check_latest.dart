import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:check_latest/check_latest.dart';
import 'package:yaml/yaml.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('root', defaultsTo: '.', help: 'Repository root containing toolchain.env and pubspec.lock.')
    ..addFlag('json', negatable: false, help: 'Print JSON instead of a Markdown table.')
    ..addFlag('report-only', negatable: false, help: 'Always exit 0, even when something is behind.')
    ..addFlag('skip-pub', negatable: false, help: 'Only check the toolchain and forks.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(parser.usage);
    exit(64);
  }
  if (options.flag('help')) {
    stdout
      ..writeln('Usage: dart run check_latest [options]')
      ..writeln(parser.usage);
    return;
  }

  final root = options.option('root')!;
  final env = readEnvFile(File('$root/toolchain.env').readAsStringSync());
  // This hosted release is vendored solely for the display API migration.
  // Its path override must not make the upstream version disappear from checks.
  final windowManager = File('$root/third_party/window_manager/pubspec.yaml');
  if (windowManager.existsSync()) {
    env['WINDOW_MANAGER_UPSTREAM_VERSION'] = (loadYaml(windowManager.readAsStringSync()) as YamlMap)['version']
        .toString();
  }
  final lock = File('$root/pubspec.lock');
  final Map<String, String> pub;
  if (options.flag('skip-pub') || !lock.existsSync()) {
    pub = const {};
  } else {
    final members = readWorkspaceMembers(File('$root/pubspec.yaml').readAsStringSync());
    pub = readWorkspaceDirectDependencies(lock.readAsStringSync(), [
      for (final member in members) File('$root/$member/pubspec.yaml').readAsStringSync(),
    ]);
  }

  // Published consumers remain visible when their compatibility patch is local.
  final consumers = File('$root/third_party/cross_file_consumers.json');
  if (!options.flag('skip-pub') && consumers.existsSync()) {
    final packages = jsonDecode(consumers.readAsStringSync()) as Map<String, dynamic>;
    for (final name in packages.keys) {
      final spec = loadYaml(File('$root/third_party/$name/pubspec.yaml').readAsStringSync()) as YamlMap;
      if (spec['name'] != name) throw FormatException('Vendored package name mismatch: $name');
      pub[name] = spec['version'].toString();
    }
  }

  final findings = await collect(env: env, pub: pub);
  if (options.flag('json')) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(findings.map((f) => f.toJson()).toList()));
  } else {
    stdout.write(renderMarkdown(findings));
  }

  final behind = findings.where((f) => f.isBehind).length;
  final failed = findings.where((f) => f.latest.isEmpty).length;
  stderr.writeln('check_latest: ${findings.length} items, $behind behind, $failed lookups failed');
  exitCode = findingsExitCode(findings, reportOnly: options.flag('report-only'));
}
