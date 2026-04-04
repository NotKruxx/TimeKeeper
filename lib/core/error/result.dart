// lib/core/error/result.dart

import 'failures.dart';

sealed class Result<T> {
  const Result();

  factory Result.ok(T value)        => Ok(value);
  factory Result.err(Failure failure) => Err(failure);

  bool get isOk  => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T        get value   => (this as Ok<T>).value;
  Failure  get failure => (this as Err<T>).failure;

  T?       get valueOrNull   => isOk  ? (this as Ok<T>).value     : null;
  Failure? get failureOrNull => isErr ? (this as Err<T>).failure   : null;

  R when<R>({
    required R Function(T value)    ok,
    required R Function(Failure f)  err,
  }) => switch (this) {
    Ok<T>(:final value)     => ok(value),
    Err<T>(:final failure)  => err(failure),
  };

  Result<U> map<U>(U Function(T v) fn) => switch (this) {
    Ok<T>(:final value)    => Result.ok(fn(value)),
    Err<T>(:final failure) => Result.err(failure),
  };
}

final class Ok<T>  extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final Failure failure;
  const Err(this.failure);
}

// Helper per wrappare blocchi che possono lanciare
Future<Result<T>> runCatching<T>(
  Future<T> Function() fn, {
  Failure Function(Object e, StackTrace s)? onError,
}) async {
  try {
    return Result.ok(await fn());
  } catch (e, s) {
    return Result.err(onError?.call(e, s) ?? DatabaseFailure(e.toString()));
  }
}
