import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Exceção com a mensagem REAL do erro (DNS, HTTP 401, timeout, erro SQL…).
/// Nunca descartamos a causa — ela sempre chega até a UI.
class TursoException implements Exception {
  final String message;
  TursoException(this.message);

  @override
  String toString() => message;
}

class Stmt {
  final String sql;
  final List<dynamic> args;
  const Stmt(this.sql, [this.args = const []]);
}

/// Cliente da API HTTP do Turso/libsql (endpoint /v2/pipeline).
///
/// O dashboard CAMDA Estoque usa embedded replica (libsql sync); escrever
/// direto no banco primário via HTTP faz as divergências aparecerem no
/// dashboard no próximo sync dele.
class TursoService {
  final String baseUrl;
  final String token;

  TursoService({required String url, required this.token})
      : baseUrl = normalizeUrl(url);

  /// Aceita libsql://host, https://host ou host puro.
  static String normalizeUrl(String raw) {
    var u = raw.trim();
    if (u.startsWith('libsql://')) {
      u = 'https://${u.substring('libsql://'.length)}';
    }
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  static Map<String, dynamic> _encodeArg(dynamic v) {
    if (v == null) return {'type': 'null'};
    if (v is int) return {'type': 'integer', 'value': '$v'};
    if (v is double) return {'type': 'float', 'value': v};
    return {'type': 'text', 'value': '$v'};
  }

  static dynamic _decodeCell(dynamic cell) {
    if (cell is! Map) return cell;
    switch (cell['type']) {
      case 'null':
        return null;
      case 'integer':
        return int.tryParse('${cell['value']}');
      case 'float':
        return cell['value'];
      default:
        return cell['value'];
    }
  }

  /// Executa os statements em sequência na MESMA conexão (um único request
  /// HTTP), e retorna as linhas de cada um. Erros viram TursoException com a
  /// mensagem real.
  Future<List<List<List<dynamic>>>> pipeline(List<Stmt> stmts) async {
    final body = jsonEncode({
      'requests': [
        for (final s in stmts)
          {
            'type': 'execute',
            'stmt': {
              'sql': s.sql,
              'args': s.args.map(_encodeArg).toList(),
            },
          },
        {'type': 'close'},
      ],
    });

    http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse('$baseUrl/v2/pipeline'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 25));
    } on SocketException catch (e) {
      throw TursoException(
          'Erro de rede/DNS: ${e.message}. Verifique a URL do banco e a sua internet.');
    } on TimeoutException {
      throw TursoException('Tempo esgotado (25s) ao conectar em $baseUrl.');
    } on http.ClientException catch (e) {
      throw TursoException('Erro de conexão: ${e.message}');
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw TursoException(
          'HTTP ${resp.statusCode}: token inválido, expirado ou sem permissão de escrita.');
    }
    if (resp.statusCode != 200) {
      final preview =
          resp.body.length > 300 ? '${resp.body.substring(0, 300)}…' : resp.body;
      throw TursoException('HTTP ${resp.statusCode}: $preview');
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw TursoException('Resposta inesperada do servidor (não é JSON). '
          'Confira se a URL aponta para um banco Turso.');
    }

    final out = <List<List<dynamic>>>[];
    final results = (data['results'] as List?) ?? [];
    for (final r in results) {
      if (r['type'] == 'error') {
        final msg = r['error']?['message'] ?? 'erro desconhecido';
        throw TursoException('Erro SQL: $msg');
      }
      final response = r['response'];
      if (response == null || response['type'] != 'execute') continue;
      final rows = (response['result']?['rows'] as List?) ?? [];
      out.add([
        for (final row in rows) [for (final cell in (row as List)) _decodeCell(cell)],
      ]);
    }
    return out;
  }

  Future<List<List<dynamic>>> execute(String sql,
      [List<dynamic> args = const []]) async {
    final res = await pipeline([Stmt(sql, args)]);
    return res.isEmpty ? [] : res.first;
  }

  /// Hora de Brasília (UTC−3, sem horário de verão desde 2019), no mesmo
  /// formato que o dashboard grava: "YYYY-MM-DD HH:MM:SS".
  static String agoraBrt() {
    final t = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }

  // ── Operações do app ────────────────────────────────────────────────────

  /// Testa a conexão e retorna (ok, mensagem real do resultado/erro).
  Future<(bool, String)> testConnection() async {
    try {
      final rows =
          await execute('SELECT COUNT(*) FROM estoque_mestre');
      final n = rows.isNotEmpty ? rows.first.first : 0;
      return (true, 'Conexão OK — $n produtos no estoque mestre.');
    } on TursoException catch (e) {
      return (false, e.message);
    } catch (e) {
      return (false, 'Erro inesperado: $e');
    }
  }

  Future<List<Produto>> fetchProdutos() async {
    final rows = await execute(
        'SELECT codigo, produto, categoria, qtd_sistema FROM estoque_mestre ORDER BY produto');
    return rows.map(Produto.fromRow).toList();
  }

  /// Divergências ativas (mesma tabela que alimenta a aba Divergências do dashboard).
  Future<List<Divergencia>> fetchDivergencias({String? codigo}) async {
    final where = codigo == null ? '' : ' WHERE codigo = ?';
    final rows = await execute(
      'SELECT id, codigo, produto, categoria, delta, status, cooperado, criado_em '
      'FROM divergencias$where ORDER BY criado_em DESC',
      codigo == null ? const [] : [codigo],
    );
    return rows.map(Divergencia.fromRow).toList();
  }

  /// Mesma lógica de registrar_divergencia_manual() do dashboard:
  /// grava em `divergencias` e em `historico_divergencias` (atenção: a ordem
  /// das colunas `cooperado`/`delta` difere entre as duas tabelas).
  /// delta > 0 = sobra, delta < 0 = falta. O estoque do sistema NÃO é alterado.
  Future<String> registrarDivergencia(
      Produto p, int delta, String cooperado) async {
    if (delta == 0) throw TursoException('A diferença não pode ser zero.');
    final status = delta > 0 ? 'sobra' : 'falta';
    final coop = cooperado.trim();
    final agora = agoraBrt();
    await pipeline([
      const Stmt('BEGIN'),
      Stmt(
        'INSERT INTO divergencias (codigo, produto, categoria, delta, status, cooperado, criado_em) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [p.codigo, p.produto, p.categoria, delta, status, coop, agora],
      ),
      Stmt(
        'INSERT INTO historico_divergencias (codigo, produto, categoria, cooperado, delta, status, criado_em) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [p.codigo, p.produto, p.categoria, coop, delta, status, agora],
      ),
      const Stmt('COMMIT'),
    ]);
    final sinal = delta > 0 ? '+' : '';
    final nome = coop.isEmpty ? 'sem cooperado' : coop;
    return '✅ ${p.produto} (${p.codigo}) → $status de $sinal$delta un. registrada para $nome.';
  }

  /// Mesma lógica de resolver_divergencia() do dashboard: apaga o registro e,
  /// se não restar nenhuma divergência do produto, reseta o estoque_mestre
  /// para status 'ok'.
  Future<void> resolverDivergencia(Divergencia d) async {
    await execute('DELETE FROM divergencias WHERE id = ?', [d.id]);
    final rows = await execute(
        'SELECT COUNT(*) FROM divergencias WHERE codigo = ?', [d.codigo]);
    final remaining =
        rows.isNotEmpty ? int.tryParse('${rows.first.first}') ?? 0 : 0;
    if (remaining == 0) {
      await execute(
        "UPDATE estoque_mestre SET status = 'ok', diferenca = 0, qtd_fisica = qtd_sistema, "
        "ultima_contagem = ? WHERE codigo = ? AND status IN ('falta', 'sobra')",
        [agoraBrt(), d.codigo],
      );
    }
  }
}
