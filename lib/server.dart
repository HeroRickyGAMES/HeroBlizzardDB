import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:uuid/uuid.dart';

//Programado por HeroRickyGAMES com a Ajuda de Deus!!

// --- Configuração e Banco de Dados ---
Map<String, dynamic> _config = {};
final Map<String, Map<String, dynamic>> _database = {};
final String _dbPath = 'database.json';
final Map<String, DateTime> _sessions = {};
const uuid = Uuid();

// --- Carregamento de Configurações ---
Future<void> _loadConfig() async {
  final configFile = File('config.json');
  if (await configFile.exists()) {
    final content = await configFile.readAsString();
    _config = jsonDecode(content);
    print('Arquivo de configuração carregado.');
  } else {
    print('ERRO: Arquivo config.json não encontrado. Crie um com "admin_user", "admin_password" e "api_tokens".');
    exit(1);
  }
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
      _database['exemplo'] = {'doc1': {'id': 'doc1', 'mensagem': 'Bem-vindo!'}};
      await _saveDatabase();
    }
  } catch (e) {
    print('Erro ao carregar o banco de dados: $e');
  }
}

Future<void> _saveDatabase() async {
  try {
    final file = File(_dbPath);
    final encodedJson = jsonEncode(_database);
    await file.writeAsString(encodedJson);
  } catch (e) {
    print('Erro ao salvar o banco de dados: $e');
  }
}

// --- Middleware de Autenticação Unificado ---
Middleware authMiddleware() {
  return (Handler innerHandler) {
    return (Request request) {
      final path = request.url.path;

      // Se for uma requisição para a API...
      if (path.startsWith('api/')) {
        // 1. Tenta autenticar via Token de API (para apps externos)
        final authHeader = request.headers['authorization'];
        if (authHeader != null && authHeader.startsWith('Bearer ')) {
          final token = authHeader.substring(7);
          final validTokens = List<String>.from(_config['api_tokens'] ?? []);
          if (validTokens.contains(token)) {
            return innerHandler(request); // Token válido, acesso liberado
          }
        }

        // 2. Se não houver token de API, tenta autenticar via Cookie de Sessão (para a nossa UI)
        final sessionToken = _getSessionToken(request);
        if (_isSessionValid(sessionToken)) {
          return innerHandler(request); // Sessão válida, acesso liberado
        }

        // 3. Se nenhum dos dois funcionar, acesso negado.
        return Response.forbidden('Acesso negado. Token de autorização ou sessão inválida.');
      }

      // Se for uma requisição para a UI (não-API)...
      if (path == 'login.html' || path.endsWith('.css') || path.endsWith('.js') || path == 'login') {
        return innerHandler(request);
      }

      final sessionToken = _getSessionToken(request);
      if (!_isSessionValid(sessionToken)) {
        return Response.seeOther('/login.html'); // Redireciona se não tiver sessão
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
    if (sessionEntry.isNotEmpty) {
      return sessionEntry.split('=').last;
    }
  }
  return null;
}

bool _isSessionValid(String? token) {
  if (token == null) return false;
  return _sessions.containsKey(token) && _sessions[token]!.isAfter(DateTime.now());
}


void main() async {
  await _loadConfig();
  await _loadDatabase();

  final router = Router();

  // --- Rotas da UI ---
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

  // --- Rotas da API ---
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
      final Map<String, dynamic> docData = jsonDecode(body);
      final newId = docData.containsKey('id') && docData['id'] != null && docData['id'].toString().isNotEmpty ? docData['id'].toString() : uuid.v4();
      docData['id'] = newId;
      if (!_database.containsKey(collection)) _database[collection] = {};
      _database[collection]![newId] = docData;
      await _saveDatabase();
      return Response(201, body: jsonEncode(docData), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response(400, body: 'JSON inválido.');
    }
  });

  router.put('/api/<collection>/<id>', (Request request, String collection, String id) async {
    if (!_database.containsKey(collection) || !_database[collection]!.containsKey(id)) return Response.notFound('Documento com ID "$id" não encontrado na coleção "$collection".');
    final body = await request.readAsString();
    try {
      final Map<String, dynamic> docData = jsonDecode(body);
      docData['id'] = id;
      _database[collection]![id] = docData;
      await _saveDatabase();
      return Response.ok(jsonEncode(docData), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response(400, body: 'JSON inválido.');
    }
  });

  router.delete('/api/<collection>', (Request request, String collection) async {
    if (_database.containsKey(collection)) {
      _database.remove(collection);
      await _saveDatabase();
      return Response(204);
    } else {
      return Response.notFound('Coleção "$collection" não encontrada.');
    }
  });

  router.delete('/api/<collection>/<id>', (Request request, String collection, String id) async {
    if (!_database.containsKey(collection) || !_database[collection]!.containsKey(id)) return Response.notFound('Documento com ID "$id" não encontrado na coleção "$collection".');
    _database[collection]!.remove(id);
    await _saveDatabase();
    return Response(204);
  });

  // Handler para arquivos estáticos (HTML, CSS, JS)
  final staticHandler = createStaticHandler('public', defaultDocument: 'index.html');

  // Combina os handlers: primeiro tenta as rotas, depois os arquivos estáticos
  final cascadeHandler = Cascade()
      .add(router.call)
      .add(staticHandler)
      .handler;

  final server = await io.serve(
    Pipeline()
        .addMiddleware(logRequests()) // Adiciona logs para depuração
        .addMiddleware(authMiddleware()) // Aplica o middleware de segurança unificado
        .addHandler(cascadeHandler),
    'localhost',
    8080,
  );

  print('Servidor HeroBlizzardDB rodando em http://localhost:8080');
}