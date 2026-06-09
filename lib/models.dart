class Produto {
  final String codigo;
  final String produto;
  final String categoria;
  final int qtdSistema;

  const Produto({
    required this.codigo,
    required this.produto,
    required this.categoria,
    required this.qtdSistema,
  });

  factory Produto.fromRow(List<dynamic> row) => Produto(
        codigo: '${row[0] ?? ''}',
        produto: '${row[1] ?? ''}',
        categoria: '${row[2] ?? ''}',
        qtdSistema: int.tryParse('${row[3] ?? 0}') ?? 0,
      );

  String get label => '$codigo — $produto';
}

class Divergencia {
  final int id;
  final String codigo;
  final String produto;
  final String categoria;
  final int delta;
  final String status;
  final String cooperado;
  final String criadoEm;

  const Divergencia({
    required this.id,
    required this.codigo,
    required this.produto,
    required this.categoria,
    required this.delta,
    required this.status,
    required this.cooperado,
    required this.criadoEm,
  });

  factory Divergencia.fromRow(List<dynamic> row) => Divergencia(
        id: int.tryParse('${row[0] ?? 0}') ?? 0,
        codigo: '${row[1] ?? ''}',
        produto: '${row[2] ?? ''}',
        categoria: '${row[3] ?? ''}',
        delta: int.tryParse('${row[4] ?? 0}') ?? 0,
        status: '${row[5] ?? ''}',
        cooperado: '${row[6] ?? ''}',
        criadoEm: '${row[7] ?? ''}',
      );

  String get deltaFmt => delta > 0 ? '+$delta' : '$delta';
}
