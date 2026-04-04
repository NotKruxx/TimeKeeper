// lib/core/error/failures.dart

sealed class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

final class DatabaseFailure   extends Failure { const DatabaseFailure(super.message); }
final class NetworkFailure    extends Failure { const NetworkFailure(super.message); }
final class NotFoundFailure   extends Failure { const NotFoundFailure(super.message); }
final class ValidationFailure extends Failure { const ValidationFailure(super.message); }
final class AuthFailure       extends Failure { const AuthFailure(super.message); }
final class ConflictFailure   extends Failure { const ConflictFailure(super.message); }
