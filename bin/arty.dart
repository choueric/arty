import 'package:arty/arty.dart' as arty;
import 'package:path/path.dart' as Path;
import 'package:http/http.dart' as http;
import 'package:args/args.dart';
import 'package:filesize/filesize.dart';
import 'package:args/command_runner.dart';
import 'package:dolumns/dolumns.dart';
import 'dart:convert';
import 'dart:io';

bool verbose = false;

class FileListItem {
  final String uri;
  final int size;
  final DateTime lastModified;
  final bool folder;

  FileListItem.fromJson(Map<String, dynamic> json)
      : uri = json['uri'],
        size = json['size'],
        lastModified = DateTime.parse(json['lastModified']),
        folder = json['folder'] {}

  List<String> forOutput() {
    if (folder) {
      return ['$uri/', '${lastModified.toString()}', ''];
    } else {
      return [uri, '${lastModified.toString()}', '${filesize(size)}'];
    }
  }
}

class Repo {
  final String token;
  final String name;
  final String baseUri;
  final String key;
  final String baseFolderPath;

  Repo(this.token, this.name, this.baseUri, this.key, this.baseFolderPath);

  String buildURI(String subpath) {
    return '$baseUri/$key/$baseFolderPath/$subpath';
  }

  Future<Map<String, dynamic>> getRspJson(String uri) async {
    final response = await http.get(
      Uri.parse(baseUri + uri),
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
      Uri.parse(baseUri + uri),
      headers: {
        'X-JFrog-Art-Api': token,
      },
    );
  }

  String toString() {
    return '[$name]: $key/$baseFolderPath';
  }

  void download(String uri, String output) async {
    bool validURI = Uri.parse(uri).isAbsolute;
    if (!validURI) uri = buildURI(uri);

    var request = http.Request("GET", Uri.parse(uri));
    request.headers['X-JFrog-Art-Api'] = token;

    final client = new http.Client();
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
      stdout.write("\r$received | $length ($percent%)");
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

  Future<String> fileDownloadUri(String fileSubPath) async {
    var uri = '/api/storage/' + key + '/' + baseFolderPath;
    uri = uri + '/' + fileSubPath;
    var rspJson = await getRspJson(uri);
    if (verbose) print('$rspJson\n');
    var children = rspJson['children'];
    if (children != null) {
      print('error: ${fileSubPath} is a folder');
      return "";
    }
    print('created     : ${rspJson['created']}');
    print('lastModified: ${rspJson['lastModified']}');
    print('lastUpdated : ${rspJson['lastUpdated']}');
    print('size        : ${rspJson['size']}');
    return rspJson['downloadUri'];
  }

  /* File List */
  void fileList(String? subPath, int limit) async {
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

    List<FileListItem> fileList = [];
    for (final ele in files) fileList.add(FileListItem.fromJson(ele));
    fileList.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    int count = 0;
    List<List<String>> forOutput = [];
    for (final i in fileList) {
      if (limit != 0 && ++count > limit) {
        print('Only list latest ${limit} items');
        break;
      }
      var l = ['-', ...i.forOutput()];
      forOutput.add(l);
    }
    print(dolumnify(forOutput));
    if (limit != 0 && (fileList.length - limit != 0))
      print('${fileList.length - limit} entries more ...');
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
  final String baseUri;
  Map<String, Repo> repoMap = Map();

  Config.fromJson(Map<String, dynamic> json)
      : currentRepo = json[keyCurrent],
        token = json[keyToken],
        baseUri = json[keyBaseUri] {
    for (var r in json[keyRepoList]) {
      final String name = r[keyRepoName];
      repoMap[name] =
          Repo(token, name, baseUri, r[keyRepoKey], r[keyRepoFolderPath]);
    }
  }

  Repo? repo(String name) => repoMap[name];

  String toString() {
    var ret = 'Current repo: $currentRepo\n';
    repoMap.forEach((k, v) {
      if (k == currentRepo)
        ret += '* $v\n';
      else
        ret += '  $v\n';
    });
    return ret;
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> obj = {
      keyCurrent: currentRepo,
      keyBaseUri: baseUri,
      keyToken: token,
    };
    var repoList = <Map<String, dynamic>>[];
    repoMap.forEach((k, v) {
      Map<String, dynamic> repo = {
        keyRepoName: k,
        keyRepoKey: v.key,
        keyRepoFolderPath: v.baseFolderPath,
      };
      repoList.add(repo);
    });
    obj[keyRepoList] = repoList;
    return obj;
  }
}

Future<Map<String, dynamic>> readJson(String filePath) async {
  var file = File(filePath);
  return await json.decode(await file.readAsString());
}

void writeJson(Map<String, dynamic> jsonObj, String filePath) async {
  var encoder = new JsonEncoder.withIndent('  ');
  var jsonString = encoder.convert(jsonObj);
  File(filePath).openWrite()
    ..write(jsonString)
    ..close();
}

class ListCommand extends Command {
  final String name = "list";
  final String description = "list the defined repos in the configuration file";
  final Config config;

  ListCommand(this.config) {}

  void run() {
    print('$config');
  }
}

class ChooseCommand extends Command {
  final String name = "choose";
  final String description = "choose the current repo profile";
  final Config config;
  final String configPath;

  ChooseCommand(this.config, this.configPath) {}

  void run() {
    var args = argResults;
    if (args == null || args.rest.length == 0) {
      print('Must specify a repo to choose as current one');
      return;
    }

    final repoName = args.rest[0];
    var repo = config.repo(repoName);
    if (repo == null) {
      print('Could not find repo $repoName');
      return;
    }
    config.currentRepo = repoName;
    var jsonObj = config.toJson();
    writeJson(jsonObj, configPath);
  }
}

class LsCommand extends Command {
  final String name = "ls";
  final String description = "ls the files on the Artifactory";
  final Config config;

  LsCommand(this.config) {
    argParser.addOption('limit',
        abbr: 'l',
        help: 'list the latest limited items. 0 means no limit',
        defaultsTo: '10');
  }

  void run() {
    var repo = config.repo(config.currentRepo)!;
    String? subpath = null;
    var args = argResults;
    if (args != null && args.rest.length > 0) {
      subpath = args.rest[0];
    }
    int limit = int.parse(argResults?['limit']);
    repo.fileList(subpath, limit);
  }
}

class GetCommand extends Command {
  final String name = "get";
  final String description = "download the artifact on the Artifactory";
  final Config config;

  GetCommand(this.config) {
    argParser.addOption('out',
        abbr: 'o',
        help: "file to save the downloaded artifactory",
        defaultsTo: '');
  }

  void run() async {
    var args = argResults;
    if (args == null || args.rest.length == 0) {
      print('Must specify a repo to choose as current one');
      return;
    }

    final fileSubPath = args.rest[0];
    var out = args['out'];
    if (out == '') {
      final s = fileSubPath.split('/');
      out = s[s.length - 1];
    }

    var repo = config.repo(config.currentRepo)!;
    final downloadUri = await repo.fileDownloadUri(fileSubPath);
    if (downloadUri == "") return;
    repo.download(downloadUri, out);
  }
}

void main(List<String> arguments) async {
  var homePath = Platform.environment['HOME']!;
  var configPath = Path.join(homePath, '.arty.json');
  var config = Config.fromJson(await readJson(configPath));

  var runner =
      CommandRunner("arty", "A dart implementation of jfrog for Artifactory.")
        ..addCommand(ListCommand(config))
        ..addCommand(ChooseCommand(config, configPath))
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
