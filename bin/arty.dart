import 'package:arty/arty.dart' as arty;
import 'package:path/path.dart' as Path;
import 'package:http/http.dart' as http;
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'dart:convert';
import 'dart:io';

bool verbose = false;
const String ArtifactoryBaseURL =
    "https://artifact.invencolabs.com/artifactory";

class Repo {
  final String token;
  final String name;
  final String baseUri;
  final String key;
  final String baseFolderPath;

  Repo(this.token, this.name, this.baseUri, this.key, this.baseFolderPath);

  Future<Map<String, dynamic>> getRspJson(String uri) async {
    final response = await http.get(
      Uri.parse(ArtifactoryBaseURL + uri),
      headers: {
        'X-JFrog-Art-Api': token,
      },
    );
    if (response.statusCode != 200) {
      print('Error: response status ${response.statusCode}');
      print('> ${response.body}');
      return {};
    }
    final responseJson = jsonDecode(response.body);
    return responseJson;
  }

  Future<http.Response> doRestful(String uri) async {
    return await http.get(
      Uri.parse(ArtifactoryBaseURL + uri),
      headers: {
        'X-JFrog-Art-Api': token,
      },
    );
  }

  void dump() {
    print('[$name]: $key -> $baseFolderPath');
  }

  void download(String uri, String output) async {
    final client = new http.Client();
    var request = http.Request("GET", Uri.parse(uri));
    request.headers['X-JFrog-Art-Api'] = token;
    http.StreamedResponse response = await client.send(request);
    if (response.statusCode != 200) {
      print('Error: response status ${response.statusCode}');
      client.close();
      return;
    }
    var length = response.contentLength!;
    int received = 0;
    var f = File(output);
    var sink = f.openWrite();
    await response.stream.map((s) {
      received += s.length;
      var percent = ((received / length) * 100).round();
      stdout.write("\r$percent %");
      return s;
    }).pipe(sink);
    sink.close();
    client.close();
    print('\nSaved as $output');
  }

  /* folderInfo and fileInfo */
  void storageInfo(String? subPath) async {
    var uri = '/api/storage/' + key + '/' + baseFolderPath;
    if (subPath != null) uri = uri + '/' + subPath;
    var rspJson = await getRspJson(uri);
    if (verbose) print('$rspJson\n');
    print('${rspJson['uri']}');
    var children = rspJson['children'];
    if (children == null) {
      // file info
      print('created     : ${rspJson['created']}');
      print('lastModified: ${rspJson['lastModified']}');
      print('lastUpdated : ${rspJson['lastUpdated']}');
      print('size        : ${rspJson['size']}');
      print('downloadUri : ${rspJson['downloadUri']}');
    } else {
      // folder info
      print('created     : ${rspJson['created']}');
      print('lastModified: ${rspJson['lastModified']}');
      print('lastUpdated : ${rspJson['lastUpdated']}');
      if (children.length == 0) {
        print('0 result, empty folder');
        return;
      }
      for (final ele in children) {
        print('- ${ele['uri']}');
      }
    }
  }

  /* File List */
  void fileList(String? subPath) async {
    var uri = '/api/storage/' + key + '/' + baseFolderPath;
    if (subPath != null) uri = uri + '/' + subPath;
    uri = uri + '?list&listFolders=1';
    var rsp = await doRestful(uri);
    if (rsp.statusCode == 400) {
      /* Expected a folder but found a file */
      storageInfo(subPath);
      return;
    }
    final rspJson = jsonDecode(rsp.body);
    if (verbose) print('$rspJson\n');
    var files = rspJson['files'];
    print('${rspJson['uri']}');
    print('created     : ${rspJson['created']}');
    if (files.length == 0) {
      print('0 result, empty folder');
      return;
    }
    for (final ele in files) {
      if (ele['folder']) {
        print('- ${ele['uri']}/\t${ele['lastModified']}');
      } else {
        print('- ${ele['uri']}\t${ele['lastModified']}\t${ele['size']}');
      }
    }
  }
}

class Config {
  static const String keyCurrent = 'current';
  static const String keyBaseUri = 'baseUri';
  static const String keyToken = 'token';
  static const String keyRepoList = 'repoList';
  static const String keyRepoName = 'name';
  static const String keyRepoKey = 'key';
  static const String keyRepoFolderPath = 'folderPath';

  String currentRepo;
  final String token;
  Map<String, Repo> repoMap = Map();

  Config.fromJson(Map<String, dynamic> json)
      : currentRepo = json[keyCurrent],
        token = json[keyToken] {
    final String baseUri = json[keyBaseUri]!;
    for (var r in json[keyRepoList]) {
      final String name = r[keyRepoName];
      repoMap[name] =
          Repo(token, name, baseUri, r[keyRepoKey], r[keyRepoFolderPath]);
    }
  }

  Repo repo(String name) => repoMap[name]!;
  void dump() {
    print('Current repo: $currentRepo');
    repoMap.forEach((k, v) => v.dump());
  }
}

Future<Map<String, dynamic>> readJson(String filePath) async {
  var file = File(filePath);
  return await json.decode(await file.readAsString());
}

class ListCommand extends Command {
  final String name = "list";
  final String description = "list the defined repos in the configuration file";
  final Config config;

  ListCommand(this.config) {}

  void run() {
    config.dump();
  }
}

class LsCommand extends Command {
  final String name = "ls";
  final String description = "ls the files on the Artifactory";
  final Config config;

  LsCommand(this.config) {
    argParser.addOption('subpath',
        abbr: 's', help: 'subpath inside the repo base folder', defaultsTo: '');
  }

  void run() {
    var repo = config.repo(config.currentRepo);
    String? subpath = argResults?['subpath'];
    repo.fileList(subpath);
  }
}

class GetCommand extends Command {
  final String name = "get";
  final String description = "download the artifact on the Artifactory";
  final Config config;

  GetCommand(this.config) {
    argParser.addOption('uri',
        abbr: 'u', help: "downloadUri from 'ls' command", mandatory: true);
    argParser.addOption('out',
        abbr: 'o',
        help: "file to save the downloaded artifactory",
        defaultsTo: '');
  }

  void run() {
    final uri = argResults?['uri'];
    var out = argResults?['out'];
    if (out == '') {
      final s = uri.split('/');
      out = s[s.length - 1];
    }

    var repo = config.repo(config.currentRepo);
    repo.download(uri, out);
  }
}

void main(List<String> arguments) async {
  var homePath = Platform.environment['HOME']!;
  var configPath = Path.join(homePath, '.arty.json');
  var config = Config.fromJson(await readJson(configPath));

  var runner =
      CommandRunner("arty", "A dart implementation of jfrog for Artifactory.")
        ..addCommand(ListCommand(config))
        ..addCommand(LsCommand(config))
        ..addCommand(GetCommand(config));

  runner.argParser.addFlag('verbose',
      abbr: 'v',
      defaultsTo: false,
      help: 'verbose print', callback: (_verbose) {
    verbose = _verbose;
  });

  runner.run(arguments).catchError((error) {
    if (error is! UsageException) throw error;
    print(error);
    exit(64); // Exit code 64 indicates a usage error.
  });
}
