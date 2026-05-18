// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_typesense/otel_typesense.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_typesense-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('search records CLIENT span with found + time', () async {
    await tracedTypesenseSearch<String>(
      collection: 'books',
      query: 'dune',
      perPage: 25,
      queryBy: 'title,author',
      invoke: () async => const TypesenseSearchResult(
        value: 'rows',
        found: 11,
        searchTimeMs: 4,
      ),
    );
    final span = spans.findSpanByName('typesense search books');
    expect(span, isNotNull);
    expect(span!.kind, SpanKind.client);
    final a = attrsOf(span);
    expect(a['db.system'], 'typesense');
    expect(a['db.collection.name'], 'books');
    expect(a['typesense.query'], 'dune');
    expect(a['typesense.per_page'], 25);
    expect(a['typesense.query_by'], 'title,author');
    expect(a['typesense.found'], 11);
    expect(a['typesense.search_time_ms'], 4);
  });

  test('import records CLIENT span with document count', () async {
    await tracedTypesenseIndexOp<String>(
      operation: 'import',
      collection: 'books',
      documentCount: 500,
      invoke: () async => 'ok',
    );
    final a = attrsOf(spans.findSpanByName('typesense import books')!);
    expect(a['db.operation'], 'import');
    expect(a['typesense.document_count'], 500);
  });

  test('records exception', () async {
    await expectLater(
      tracedTypesenseSearch<String>(
        collection: 'c',
        query: 'q',
        invoke: () async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      spans.findSpanByName('typesense search c')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutTypesenseInstrumentationAsync(() async {
      await tracedTypesenseSearch<String>(
        collection: 'c',
        query: 'q',
        invoke: () async => const TypesenseSearchResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('typesense '), isEmpty);
  });
}
