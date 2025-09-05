import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bcrypt/bcrypt.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

//Programado por HeroRickyGAMES

final Map<String, dynamic> _config = {};
final Map<String, Map<String, dynamic>> _database = {};
String _dbPath = 'database.json';
final Map<String, DateTime> _sessions = {};
const uuid = Uuid();
final _dbLock = Lock();

// --- Componentes para o sistema de Batching ---
bool _isDbDirty = false;
Timer? _dbSaveTimer;

// --- Carregamento de Configuração Híbrida ---
Future<void> _loadConfig() async {
  Map<String, dynamic> fileConfig = {};
  final configFile = File('config.json');
  if (await configFile.exists()) {
    try {
      final content = await configFile.readAsString();
      fileConfig = jsonDecode(content);
      print('Arquivo config.json carregado como base.');
    } catch (e) {
      print('Aviso: Falha ao ler o config.json. Erro: $e');
    }
  }

  _config['admin_user'] = Platform.environment['RENDER_DISCOVERY_SERVICE'] ?? fileConfig['admin_user'];
  _config['admin_password'] = Platform.environment['RENDER_SERVICE_ID'] ?? fileConfig['admin_password'];
  _config['import_export_password'] = Platform.environment['RENDER_SERVICE_ID'];

  final apiTokensEnv = Platform.environment['RENDER_SERVICE_ID'];
  if (apiTokensEnv != null && apiTokensEnv.isNotEmpty) {
    _config['api_tokens'] = apiTokensEnv.split(',').where((s) => s.isNotEmpty).toList();
  } else {
    _config['api_tokens'] = fileConfig['api_tokens'] ?? [];
  }
  _dbPath = Platform.environment['DATABASE_PATH'] ?? 'database.json';

  if (_config['admin_user'] == null || _config['admin_password'] == null) {
    print('ERRO CRÍTICO: Credenciais de administrador não foram configuradas.');
    exit(1);
  }
  if (_config['import_export_password'] == null) {
    print('AVISO: Senha de import/export (IMPORT_EXPORT_PASSWORD) não definida. As rotas estarão desativadas.');
  }

  print('Configurações carregadas com sucesso.');
}

// --- Funções do Banco de Dados ---
Future<void> _loadDatabase() async {
  try {
    final file = File(_dbPath);
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
        final Map<String, dynamic> decodedData = jsonDecode(content);
        decodedData.forEach((key, value) {
          _database[key] = Map<String, dynamic>.from(value);
        });
      }
    } else {
      _database['exemplo'] = {'doc1': {'id': 'doc1', 'mensagem': 'Bem-vindo ao HeroBlizzardDB!'}};
      await File(_dbPath).writeAsString(jsonEncode(_database));
    }
  } catch (e) {
    print('Erro ao carregar o banco de dados de $_dbPath: $e');
  }
}

Future<void> _saveDatabase() async {
  await _dbLock.synchronized(() async {
    if (!_isDbDirty) return;
    try {
      final file = File(_dbPath);
      await file.writeAsString(jsonEncode(_database));
      _isDbDirty = false;
      print('${DateTime.now()}: Banco de dados salvo no disco (batch).');
    } catch (e) {
      print('Erro ao salvar o banco de dados em $_dbPath: $e');
    }
  });
}

Future<T> _safeDbWrite<T>(Future<T> Function() operation) async {
  return await _dbLock.synchronized(() async {
    final result = await operation();
    _isDbDirty = true;
    return result;
  });
}

void _startDbSaveTimer() {
  _dbSaveTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
    _saveDatabase();
  });
  print('Sistema de batching de escrita iniciado (salvando a cada 2 segundos se houver mudanças).');
}

void _stopDbSaveTimer() {
  _dbSaveTimer?.cancel();
}

void _setupShutdownHook() {
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nRecebido sinal de encerramento (Ctrl+C). Salvando alterações pendentes...');
    _stopDbSaveTimer();
    await _saveDatabase();
    print('Servidor encerrado.');
    exit(0);
  });
}

// --- Middlewares e Funções Auxiliares ---
Middleware authMiddleware() {
  return (Handler innerHandler) {
    return (Request request) {
      final path = request.url.path;

      // Rotas públicas de autenticação do app, login do painel e assets são liberadas primeiro.
      if (path.startsWith('/auth/') || path == '/login' || path == '/login.html' || path.endsWith('.css') || path.endsWith('.js')) {
        return innerHandler(request);
      }

      // Rotas da API principal (/api/*)
      if (path.startsWith('/api/')) {
        // Rotas de import/export usam senha própria na URL, então são liberadas do token/sessão
        if(path == '/api/export' || path == '/api/import') {
          return innerHandler(request);
        }
        // Validação por Token Bearer (para apps externos)
        final authHeader = request.headers['authorization'];
        if (authHeader != null && authHeader.startsWith('Bearer ')) {
          final token = authHeader.substring(7);
          final validTokens = List<String>.from(_config['api_tokens'] ?? []);
          if (validTokens.contains(token)) {
            return innerHandler(request);
          }
        }
        // Validação por Sessão de Cookie (para a dashboard)
        final sessionToken = _getSessionToken(request);
        if (_isSessionValid(sessionToken)) {
          return innerHandler(request);
        }
        return Response.forbidden('Acesso negado. Token de autorização ou sessão inválida.');
      }

      // Se não for API nem rota pública, protege o resto da UI do Admin
      final sessionToken = _getSessionToken(request);
      if (!_isSessionValid(sessionToken)) {
        return Response.seeOther('/login.html');
      }
      return innerHandler(request);
    };
  };
}

String? _getSessionToken(Request request) {
  final sessionCookie = request.headers['cookie'];
  if (sessionCookie != null) {
    final cookies = sessionCookie.split(';');
    final sessionEntry = cookies.firstWhere((c) => c.trim().startsWith('session_token='), orElse: () => '');
    if (sessionEntry.isNotEmpty) { return sessionEntry.split('=').last; }
  }
  return null;
}

bool _isSessionValid(String? token) {
  if (token == null) return false;
  return _sessions.containsKey(token) && _sessions[token]!.isAfter(DateTime.now());
}

// --- Função Principal e Definição de Rotas ---
void main() async {
  await _loadConfig();
  await _loadDatabase();
  _startDbSaveTimer();
  _setupShutdownHook();

  final router = Router();

  // Rota de Login do PAINEL ADMIN
  router.post('/login', (Request request) async {
    final body = await request.readAsString();
    final params = Uri.splitQueryString(body);
    final user = params['username'];
    final pass = params['password'];
    if (user == _config['admin_user'] && pass == _config['admin_password']) {
      final sessionToken = uuid.v4();
      _sessions[sessionToken] = DateTime.now().add(Duration(hours: 8));
      return Response.seeOther('/', headers: { 'Set-Cookie': 'session_token=$sessionToken; Path=/; HttpOnly; Max-Age=28800' });
    } else {
      return Response.seeOther('/login.html?error=1');
    }
  });

  // Rotas de AUTENTICAÇÃO para o APP FROSTGUARD
  router.post('/auth/register', (Request request) async {
    final body = await request.readAsString();
    final Map<String, dynamic> data = jsonDecode(body);
    final email = data['email']?.toString().toLowerCase();
    final password = data['password']?.toString();

    if (email == null || password == null || email.isEmpty || password.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'Email e senha são obrigatórios.'}));
    }

    return await _safeDbWrite(() async {
      if (!_database.containsKey('frostguard_users')) {
        _database['frostguard_users'] = {};
      }
      final users = _database['frostguard_users']!;
      final userExists = users.values.any((user) => user['email'] == email);
      if (userExists) {
        return Response(409, body: jsonEncode({'error': 'Este email já está em uso.'}));
      }
      final String hashedPassword = BCrypt.hashpw(password, BCrypt.gensalt());
      final newUserId = uuid.v4();
      final newUser = {
        'id': newUserId, 'email': email, 'password_hash': hashedPassword,
        'licenca_ativa_ate': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      };
      _database['frostguard_users']![newUserId] = newUser;
      return Response(201, body: jsonEncode({'id': newUserId, 'email': email}));
    });
  });

  router.post('/auth/login', (Request request) async {
    final body = await request.readAsString();
    final Map<String, dynamic> data = jsonDecode(body);
    final email = data['email']?.toString().toLowerCase();
    final password = data['password']?.toString();

    if (email == null || password == null) {
      return Response(400, body: jsonEncode({'error': 'Email e senha são obrigatórios.'}));
    }

    final users = _database['frostguard_users'];
    if (users == null) {
      return Response(401, body: jsonEncode({'error': 'Usuário ou senha inválidos.'}));
    }

    final userEntry = users.entries.firstWhere(
          (entry) => entry.value['email'] == email, orElse: () => const MapEntry('', null),
    );

    if (userEntry.value == null) {
      return Response(401, body: jsonEncode({'error': 'Usuário ou senha inválidos.'}));
    }

    final user = userEntry.value;
    final String hashedPassword = user['password_hash'];

    if (BCrypt.checkpw(password, hashedPassword)) {
      return Response.ok(jsonEncode({
        'id': user['id'], 'email': user['email'], 'licenca_ativa_ate': user['licenca_ativa_ate'],
      }));
    } else {
      return Response(401, body: jsonEncode({'error': 'Usuário ou senha inválidos.'}));
    }
  });

  // Rotas de CRUD da API
  router.get('/api/collections', (Request request) {
    final collectionNames = _database.keys.toList();
    return Response.ok(jsonEncode(collectionNames), headers: {'Content-Type': 'application/json'});
  });

  router.get('/api/<collection>', (Request request, String collection) {
    if (!_database.containsKey(collection)) return Response.notFound('Coleção "$collection" não encontrada.');
    final documents = _database[collection]!.values.toList();
    return Response.ok(jsonEncode(documents), headers: {'Content-Type': 'application/json'});
  });

  router.post('/api/<collection>', (Request request, String collection) async {
    final body = await request.readAsString();
    try {
      return await _safeDbWrite(() async {
        final Map<String, dynamic> docData = jsonDecode(body);
        final newId = docData.containsKey('id') && docData['id'] != null && docData['id'].toString().isNotEmpty ? docData['id'].toString() : uuid.v4();
        docData['id'] = newId;
        if (!_database.containsKey(collection)) _database[collection] = {};
        _database[collection]![newId] = docData;
        return Response(201, body: jsonEncode(docData), headers: {'Content-Type': 'application/json'});
      });
    } catch (e) {
      return Response(400, body: 'JSON inválido.');
    }
  });

  router.put('/api/<collection>/<id>', (Request request, String collection, String id) async {
    if (!_database.containsKey(collection) || !_database[collection]!.containsKey(id)) return Response.notFound('Documento não encontrado.');
    final body = await request.readAsString();
    try {
      return await _safeDbWrite(() async {
        final Map<String, dynamic> docData = jsonDecode(body);
        docData['id'] = id;
        _database[collection]![id] = docData;
        return Response.ok(jsonEncode(docData), headers: {'Content-Type': 'application/json'});
      });
    } catch (e) {
      return Response(400, body: 'JSON inválido.');
    }
  });

  router.delete('/api/<collection>', (Request request, String collection) async {
    if (!_database.containsKey(collection)) return Response.notFound('Coleção não encontrada.');
    return await _safeDbWrite(() async {
      _database.remove(collection);
      return Response(204);
    });
  });

  router.delete('/api/<collection>/<id>', (Request request, String collection, String id) async {
    if (!_database.containsKey(collection) || !_database[collection]!.containsKey(id)) return Response.notFound('Documento não encontrado.');
    return await _safeDbWrite(() async {
      _database[collection]!.remove(id);
      return Response(204);
    });
  });

  // Rotas de Import / Export
  router.get('/api/export', (Request request) async {
    final providedPassword = request.url.queryParameters['password'];
    final masterPassword = _config['import_export_password'];
    if (masterPassword == null || providedPassword != masterPassword) {
      return Response.forbidden('Senha de acesso inválida ou não configurada.');
    }
    final dbFile = File(_dbPath);
    if (!await dbFile.exists()) {
      return Response.notFound('Arquivo de banco de dados não encontrado.');
    }
    final fileContent = await dbFile.readAsString();
    return Response.ok(
      fileContent,
      headers: {
        'Content-Type': 'application/json',
        'Content-Disposition': 'attachment; filename="heroblizzarddb_backup_${DateTime.now().toIso8601String()}.json"'
      },
    );
  });

  router.post('/api/import', (Request request) async {
    final providedPassword = request.url.queryParameters['password'];
    final masterPassword = _config['import_export_password'];
    if (masterPassword == null || providedPassword != masterPassword) {
      return Response.forbidden('Senha de acesso inválida ou não configurada.');
    }
    final body = await request.readAsString();
    try {
      return await _dbLock.synchronized(() async {
        final newDbData = jsonDecode(body);
        if (newDbData is! Map<String, dynamic>) {
          throw FormatException('O JSON importado deve ser um objeto (Map).');
        }
        final currentDbFile = File(_dbPath);
        if (await currentDbFile.exists()) {
          await currentDbFile.rename('${_dbPath}.bak');
        }
        _database.clear();
        newDbData.forEach((key, value) {
          _database[key] = Map<String, dynamic>.from(value);
        });
        _isDbDirty = true;
        await _saveDatabase();
        return Response.ok(jsonEncode({'status': 'sucesso', 'message': 'Banco de dados importado com sucesso e salvo.'}));
      });
    } catch (e) {
      return Response(400, body: 'JSON inválido ou erro ao processar o arquivo: $e');
    }
  });

  final staticHandler = createStaticHandler('public', defaultDocument: 'index.html');
  final cascadeHandler = Cascade().add(router.call).add(staticHandler).handler;

  final portEnv = Platform.environment['PORT'];
  final port = portEnv != null ? int.parse(portEnv) : 8080;
  final server = await io.serve(
    Pipeline().addMiddleware(logRequests()).addMiddleware(authMiddleware()).addHandler(cascadeHandler),
    '0.0.0.0',
    port,
  );
  print('Servidor HeroBlizzardDB rodando em http://0.0.0.0:$port');
}