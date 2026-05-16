// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_typesense_suppression.dart';

const _tracerName = 'dartastic_otel_libs_typesense';
const _systemValue = 'typesense';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedTypesenseSearch` callback.
class TypesenseSearchResult<T> {
  const TypesenseSearchResult({
    required this.value,
    this.found,
    this.searchTimeMs,
  });
  final T value;
  final int? found;
  final int? searchTimeMs;
}

/// Wraps a Typesense `search` request in a CLIENT span.
Future<T> tracedTypesenseSearch<T>({
  required String collection,
  required String query,
  required Future<TypesenseSearchResult<T>> Function() invoke,
  int? perPage,
  String? queryBy,
}) async {
  if (typesenseInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'db.system': _systemValue,
    'db.operation': 'search',
    'db.collection.name': collection,
    'typesense.collection': collection,
    'typesense.query': query,
  };
  if (perPage != null) m['typesense.per_page'] = perPage;
  if (queryBy != null) m['typesense.query_by'] = queryBy;

  final span = _tracer().startSpan(
    'typesense search $collection',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    final extras = <Attribute<Object>>[];
    if (r.found != null) {
      extras.add(OTel.attributeInt('typesense.found', r.found!));
    }
    if (r.searchTimeMs != null) {
      extras.add(OTel.attributeInt(
        'typesense.search_time_ms',
        r.searchTimeMs!,
      ));
    }
    if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Wraps a Typesense doc indexing operation (upsert/import/delete)
/// in a CLIENT span.
Future<T> tracedTypesenseIndexOp<T>({
  required String operation,
  required String collection,
  required Future<T> Function() invoke,
  int? documentCount,
}) async {
  if (typesenseInstrumentationSuppressed()) {
    return invoke();
  }
  final m = <String, Object>{
    'db.system': _systemValue,
    'db.operation': operation,
    'db.collection.name': collection,
    'typesense.collection': collection,
  };
  if (documentCount != null) {
    m['typesense.document_count'] = documentCount;
  }

  final span = _tracer().startSpan(
    'typesense $operation $collection',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    return await invoke();
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
